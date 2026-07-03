module Rack
  class Attack
    # Use memory store if Rails cache is null_store (e.g. in test/dev)
    if Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
      Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    end

    COLLECT_PATH_PATTERN = %r{\A/api/v1/events/collect(\.[^/]+)?/?\z}

    # Runs before ApiSignatureVerification, so site_id/fingerprint here are
    # unverified client input. Only bucket by them once the request's signature
    # actually checks out (same HMAC ApiSignatureVerification will require);
    # otherwise fall back to IP alone so an attacker can't dodge the throttle
    # by naming a real site_id with a bad/missing signature, or by randomizing
    # the fingerprint on every unauthenticated request.
    def self.authenticated_site(request, body) # rubocop:disable Metrics/MethodLength
      site_id = request.headers['X-Site-Id']
      api_key_sig = request.headers['X-Api-Key']
      timestamp = request.headers['X-Timestamp']
      return nil if [site_id, api_key_sig, timestamp].any?(&:blank?)
      return nil unless ApiSignatureVerification.fresh_timestamp?(timestamp)

      site = Site.find_by(id: site_id)
      return nil unless site

      signed_ok = ApiSignatureVerification.valid_signature?(
        timestamp: timestamp, body: body, api_key: site.api_key, provided_sig: api_key_sig
      )
      signed_ok ? site : nil
    rescue ArgumentError, ActiveRecord::StatementInvalid
      nil
    end

    # Parses out the client-supplied fingerprint. Only called once a request is
    # already authenticated, since JSON parsing is wasted work for a flood of
    # invalid-credential requests that will end up in the shared no-site bucket
    # anyway.
    def self.extract_fingerprint(body)
      return nil unless body.present? && body.bytesize <= ApiSignatureVerification::MAX_BODY_BYTES

      payload = JSON.parse(body)
      payload['fingerprint'].presence || payload.dig('properties', 'fingerprint').presence
    rescue StandardError
      nil
    end

    # IP-scoped limit, checked first because it's cheap (no body read, no DB
    # lookup, no HMAC). This lets traffic from an IP that's already over the
    # cap short-circuit before the body-dependent throttle below does any
    # per-request body/DB work. It's also independent of the throttle below: a
    # signed request can freely vary its fingerprint (and thus get a fresh
    # site_id:fingerprint bucket every time from that throttle), so without
    # this an authenticated caller could flood the endpoint — and every
    # downstream reCAPTCHA verification call — from a single IP without ever
    # tripping a limit. This one applies regardless of authentication status
    # or fingerprint.
    throttle('events/collect/ip', limit: 100, period: 1.second) do |req|
      req.ip if req.path.match?(COLLECT_PATH_PATTERN) && req.post?
    end

    # Rate limit: 100 requests per second per session
    # Exceeding this returns 429 Too Many Requests.
    # We identify a session by site_id and fingerprint.
    throttle('events/collect', limit: 100, period: 1.second) do |req|
      if req.path.match?(COLLECT_PATH_PATTERN) && req.post?
        action_dispatch_req = ActionDispatch::Request.new(req.env)

        # Bound the read to the same limit ApiSignatureVerification enforces so
        # an oversized body can't be fully buffered here before that middleware
        # ever gets a chance to reject it with 413.
        action_dispatch_req.body.rewind
        body = action_dispatch_req.body.read(ApiSignatureVerification::MAX_BODY_BYTES + 1)
        action_dispatch_req.body.rewind

        # Authenticate first (a cheap HMAC compare). Only a request whose
        # signature actually verifies gets its own site_id:fingerprint bucket
        # (which requires JSON-parsing the body); everything else (missing
        # site_id, unknown site_id, or a bad signature) is bucketed by IP only
        # without ever parsing the body, so invalid-credential floods can't
        # dodge the throttle or burn CPU parsing JSON once that IP is over limit.
        site = Rack::Attack.authenticated_site(action_dispatch_req, body)

        if site
          fingerprint = Rack::Attack.extract_fingerprint(body) ||
                        Digest::SHA256.hexdigest("#{action_dispatch_req.ip}-#{action_dispatch_req.user_agent}")
          "#{site.id}:#{fingerprint}"
        else
          "no-site:#{action_dispatch_req.ip}"
        end
      end
    end

    # Custom 429 response format matching our API conventions
    self.throttled_responder = lambda do |_request_env|
      [
        429,
        { 'Content-Type' => 'application/json' },
        [{ error: 'Too Many Requests' }.to_json]
      ]
    end
  end
end
