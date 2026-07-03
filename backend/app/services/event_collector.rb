# rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
class EventCollector
  class ValidationError < StandardError; end

  ALLOWED_EVENT_TYPES = %w[pageview click scroll custom].freeze
  SCALAR_STRING_FIELDS = %w[user_agent referrer fingerprint page_url recaptcha_token occurred_at].freeze

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

    # 6. Create the event
    Event.create!(
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
      occurred_at: parse_occurred_at(payload['occurred_at'])
    )
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

  private_class_method :validate!, :sanitize_properties, :parse_occurred_at
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
