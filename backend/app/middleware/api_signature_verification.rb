class ApiSignatureVerification
  EVENTS_PATH_PATTERN = %r{\A/api/v1/events(/|\z)}
  MAX_BODY_BYTES = 32 * 1024
  DEFAULT_TIMESTAMP_TOLERANCE_SECONDS = 300

  SITE_ID_HEADER = 'X-Site-Id'.freeze
  API_KEY_HEADER = 'X-Api-Key'.freeze
  TIMESTAMP_HEADER = 'X-Timestamp'.freeze

  def self.timestamp_tolerance_seconds
    raw = ENV.fetch('API_TIMESTAMP_TOLERANCE_SECONDS', nil)
    return DEFAULT_TIMESTAMP_TOLERANCE_SECONDS if raw.blank?

    parsed = Integer(raw, 10, exception: false)
    return parsed if parsed&.positive?

    raise "API_TIMESTAMP_TOLERANCE_SECONDS is invalid: #{raw.inspect}" if Rails.env.production?

    Rails.logger.warn(
      "API_TIMESTAMP_TOLERANCE_SECONDS is invalid (#{raw.inspect}); " \
      "using default #{DEFAULT_TIMESTAMP_TOLERANCE_SECONDS}"
    )
    DEFAULT_TIMESTAMP_TOLERANCE_SECONDS
  end

  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)

    if should_verify?(request)
      verify_signature(request, env)
    else
      @app.call(env)
    end
  end

  private

  def should_verify?(request)
    request.path.match?(EVENTS_PATH_PATTERN) && request.request_method != 'OPTIONS'
  end

  def verify_signature(request, env)
    site_id, api_key_sig, timestamp = request_credentials(request)

    error = header_error(site_id, api_key_sig, timestamp)
    return unauthorized_response(error) if error

    body, oversized = read_body(request)
    return unauthorized_response("request body exceeds #{MAX_BODY_BYTES} bytes (site_id=#{site_id})") if oversized

    site = Site.find_by(id: site_id)
    unless site && valid_signature?(timestamp, body, site.api_key, api_key_sig)
      return unauthorized_response("signature verification failed (site_id=#{site_id})")
    end

    @app.call(env)
  end

  def request_credentials(request)
    [request.headers[SITE_ID_HEADER], request.headers[API_KEY_HEADER], request.headers[TIMESTAMP_HEADER]]
  end

  def header_error(site_id, api_key_sig, timestamp)
    if [site_id, api_key_sig, timestamp].any?(&:blank?)
      return "missing #{SITE_ID_HEADER}, #{API_KEY_HEADER} or #{TIMESTAMP_HEADER} header"
    end

    parsed_timestamp = Integer(timestamp, 10, exception: false)
    return "invalid #{TIMESTAMP_HEADER} format (site_id=#{site_id})" unless parsed_timestamp

    "timestamp out of tolerance (site_id=#{site_id})" unless fresh_timestamp?(parsed_timestamp)
  end

  def fresh_timestamp?(parsed_timestamp)
    (Time.now.to_i - parsed_timestamp).abs <= self.class.timestamp_tolerance_seconds
  end

  def valid_signature?(timestamp, body, api_key, provided_sig)
    expected_sig = OpenSSL::HMAC.hexdigest('SHA256', api_key, "#{timestamp}.#{body}")
    ActiveSupport::SecurityUtils.secure_compare(expected_sig, provided_sig)
  end

  def read_body(request)
    return ['', false] unless request.body

    body = request.body.read(MAX_BODY_BYTES + 1)
    request.body.rewind
    body ||= ''

    [body, body.bytesize > MAX_BODY_BYTES]
  end

  def unauthorized_response(log_reason)
    Rails.logger.warn("ApiSignatureVerification: #{LogSanitizer.strip_control_characters(log_reason)}")

    [
      401,
      { 'Content-Type' => 'application/json', 'Date' => Time.now.httpdate },
      [{ error: 'Unauthorized' }.to_json]
    ]
  end
end
