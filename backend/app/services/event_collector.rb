# rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ClassLength
class EventCollector
  class ValidationError < StandardError; end

  ALLOWED_EVENT_TYPES = %w[pageview click scroll custom].freeze
  SCALAR_STRING_FIELDS = %w[user_agent referrer fingerprint page_url recaptcha_token occurred_at].freeze

  # Marker property the tracking snippet stamps onto its internal Web Vitals
  # ping. The ping is sent as a normal custom event so it can reuse the collect
  # endpoint and populate WebVital rows, but traffic aggregation must exclude it
  # (see AnalyticsEngine): a page held open past the session cutoff produces a
  # fresh session whose only event is this unload ping, which would otherwise
  # inflate session totals with zero-pageview sessions. Single source of truth
  # shared by SnippetBuilder (emits it) and AnalyticsEngine (filters on it).
  INTERNAL_VITALS_PROPERTY = 'wia_vitals'.freeze

  # Web Vitals metric target column => accepted property source keys. Shared by
  # validate! (to require page_url up front) and the persistence branch so the
  # two never drift.
  VITAL_KEY_GROUPS = {
    lcp_ms: %w[lcp_ms lcp],
    fid_ms: %w[fid_ms fid],
    cls_score: %w[cls_score cls],
    ttfb_ms: %w[ttfb_ms ttfb],
    fcp_ms: %w[fcp_ms fcp]
  }.freeze

  # Accepted value ranges per vital column, matching the DB column types. The
  # integer columns are 32-bit (PostgreSQL integer), and cls_score is a
  # decimal(6,4). Client-supplied values outside these ranges are rejected with
  # a 400 in validate! so WebVital.create! can never raise mid-insert.
  PG_INTEGER_MAX = 2_147_483_647
  CLS_SCORE_MAX = 99.9999
  VITAL_RANGES = {
    lcp_ms: (0..PG_INTEGER_MAX),
    fid_ms: (0..PG_INTEGER_MAX),
    cls_score: (0.0..CLS_SCORE_MAX),
    ttfb_ms: (0..PG_INTEGER_MAX),
    fcp_ms: (0..PG_INTEGER_MAX)
  }.freeze

  def self.collect(payload, site_id:, fallback_user_agent:, ip:, fallback_referrer:)
    # 1. Validate payload fields (must run before any payload[...] access below)
    validate!(payload)

    user_agent = payload['user_agent'].presence || fallback_user_agent
    referrer = payload['referrer'].presence || fallback_referrer

    # 2. Verify reCAPTCHA v3 token (score threshold 0.5)
    recaptcha_token = payload['recaptcha_token']
    raise ValidationError, 'reCAPTCHA verification failed' unless RecaptchaValidator.verify(recaptcha_token, ip)

    # 3. Detect bots
    is_bot = BotDetector.bot?(
      user_agent: user_agent,
      ip: ip,
      properties: payload['properties'],
      event_type: payload['event_type'],
      x_ratio: payload['x_ratio'],
      y_ratio: payload['y_ratio']
    )

    # 4. Resolve fingerprint (body params or fallback to IP+UA hash). Always
    # hash the resolved value to a fixed-length digest before it reaches
    # SessionManager: sessions.fingerprint is part of a btree index, and an
    # unbounded client-supplied fingerprint can exceed the index entry size
    # limit and make Session.create! raise for an otherwise valid request.
    client_fingerprint = payload['fingerprint'].presence || payload.dig('properties', 'fingerprint').presence
    fingerprint = Digest::SHA256.hexdigest(client_fingerprint || "#{ip}-#{user_agent}")

    # 5. Retrieve or initialize the visitor session
    session = SessionManager.find_or_create_session(
      site_id: site_id,
      fingerprint: fingerprint,
      referrer: referrer,
      page_url: payload['page_url'],
      is_bot: is_bot,
      payload: payload
    )

    # 6. Create the event and its Web Vitals in one transaction. validate! has
    # already rejected out-of-range vital values with a 400, but wrapping both
    # writes guarantees that any unforeseen failure on the WebVital insert can
    # never leave a partial write (an Event row with no matching vitals).
    vitals = extract_vitals(payload['properties'])
    occurred_at = parse_occurred_at(payload['occurred_at'])

    event = ActiveRecord::Base.transaction do
      created_event = Event.create!(
        site_id: site_id,
        session_id: session.id,
        event_type: payload['event_type'],
        page_url: payload['page_url'],
        referrer: referrer,
        user_agent: user_agent,
        properties: sanitize_properties(payload['properties']),
        x_ratio: payload['x_ratio'],
        y_ratio: payload['y_ratio'],
        is_bot: is_bot,
        occurred_at: occurred_at
      )

      if vitals.values.any?
        WebVital.create!(
          vitals.merge(
            site_id: site_id,
            session_id: session.id,
            page_url: payload['page_url'],
            created_at: occurred_at
          )
        )
      end

      created_event
    end

    # 7. Update site to verified if it is not already
    site = Site.find_by(id: site_id)
    site.update!(verified: true) if site && !site.verified?

    event
  end

  def self.parse_occurred_at(value)
    return Time.current if value.blank?

    Time.zone.parse(value) || Time.current
  rescue ArgumentError
    Time.current
  end

  def self.validate!(payload)
    # Ensure payload is a JSON object
    raise ValidationError, 'Payload must be a JSON object' unless payload.is_a?(Hash)
    raise ValidationError, 'Payload is required' if payload.blank?

    # event_type validation
    event_type = payload['event_type']
    if event_type.blank? || ALLOWED_EVENT_TYPES.exclude?(event_type)
      raise ValidationError,
            "Invalid event_type: '#{event_type}'. Allowed event types are: #{ALLOWED_EVENT_TYPES.join(', ')}"
    end

    # properties hash size validation
    properties = payload['properties']
    unless properties.nil?
      raise ValidationError, 'properties must be a valid JSON object/hash' unless properties.is_a?(Hash)

      if properties.keys.size > 50
        raise ValidationError, "properties exceeds the limit of 50 keys (keys count: #{properties.keys.size})"
      end
    end

    # Optional fields that must be scalar strings if present. Without this, a
    # non-scalar value (e.g. user_agent: {} or fingerprint: {}) sails through
    # validation and later crashes BotDetector#downcase or an ActiveRecord
    # assignment with a 500 instead of a clean 400.
    SCALAR_STRING_FIELDS.each do |field|
      value = payload[field]
      next if value.nil? || value.is_a?(String)

      raise ValidationError, "#{field} must be a string (got: #{value.class})"
    end

    if properties.is_a?(Hash) && properties.key?('fingerprint')
      nested_fingerprint = properties['fingerprint']
      unless nested_fingerprint.is_a?(String)
        raise ValidationError, "properties.fingerprint must be a string (got: #{nested_fingerprint.class})"
      end
    end

    # Web Vitals require a page_url. Without this check a payload carrying a
    # vital metric but no page_url passes validation, persists the Event, then
    # blows up on WebVital's page_url presence validation — a 500 with a partial
    # write. Fail fast here with a clean 400 before anything is written.
    if properties.is_a?(Hash) && vital_present?(properties) && payload['page_url'].blank?
      raise ValidationError, 'page_url is required when Web Vitals metrics are present'
    end

    # Web Vitals range validations. A parseable but out-of-range value (e.g.
    # lcp_ms beyond the 32-bit integer column, or cls_score above decimal(6,4))
    # would otherwise raise on WebVital.create! after the Event is inserted.
    # Reject it here with a 400 so no partial write occurs.
    validate_vital_ranges!(properties)

    # x_ratio and y_ratio range validations (0.0 to 1.0).
    # `.present?` treats `false` as blank, which used to let it skip
    # validation entirely and get cast to 0.0 by ActiveRecord as if it were
    # a real coordinate. Only nil (absent/explicitly cleared) should skip.
    %w[x_ratio y_ratio].each do |coord|
      next unless payload.key?(coord)

      value = payload[coord]
      next if value.nil?

      val = Float(value, exception: false)
      if val.nil? || val < 0.0 || val > 1.0
        raise ValidationError, "#{coord} must be a number between 0.0 and 1.0 (got: #{value.inspect})"
      end
    end
  end

  def self.sanitize_properties(properties)
    return {} if properties.blank?

    properties.stringify_keys
  end

  # True when the properties hash carries a PARSEABLE Web Vitals metric — the
  # same values extract_vitals would persist. Used by validate! to require
  # page_url only when a real metric is present. A custom property that merely
  # shares a generic vital alias name but holds a non-numeric value (e.g.
  # cls: "foo") is unparseable and ignored downstream, so it must not newly
  # reject an otherwise valid custom event that omits page_url.
  def self.vital_present?(properties)
    extract_vitals(properties).values.any?
  end

  # Parses the Web Vitals metrics out of the properties hash into their target
  # columns. cls_score is a float; the others are integers. Unparseable or
  # absent values become nil so a single bad metric does not reject the rest.
  def self.extract_vitals(properties)
    return VITAL_KEY_GROUPS.transform_values { nil } unless properties.is_a?(Hash)

    VITAL_KEY_GROUPS.each_with_object({}) do |(column, keys), acc|
      raw = keys.filter_map { |key| properties[key] }.first
      acc[column] =
        if raw.blank?
          nil
        elsif column == :cls_score
          Kernel.Float(raw, exception: false)
        else
          Kernel.Integer(raw, exception: false)
        end
    end
  end

  # Rejects parseable Web Vitals values that fall outside their DB column range
  # with a 400. Reuses extract_vitals, so absent/unparseable values (already
  # nil there) are skipped and only real, storable-looking numbers are checked.
  def self.validate_vital_ranges!(properties)
    return unless properties.is_a?(Hash)

    extract_vitals(properties).each do |column, value|
      next if value.nil?

      range = VITAL_RANGES[column]
      next if range.cover?(value)

      raise ValidationError, "#{column} is out of the accepted range #{range} (got: #{value})"
    end
  end

  private_class_method :validate!, :sanitize_properties, :parse_occurred_at, :vital_present?, :extract_vitals,
                       :validate_vital_ranges!
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ClassLength
