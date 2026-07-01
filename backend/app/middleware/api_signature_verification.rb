class ApiSignatureVerification
  EVENTS_PATH_PATTERN = %r{\A/api/v1/events(/|\z)}
  MAX_BODY_BYTES = 32 * 1024

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
    site_id = request.headers['X-Site-Id']
    api_key_sig = request.headers['X-Api-Key']

    return unauthorized_response('missing X-Site-Id or X-Api-Key header') if site_id.blank? || api_key_sig.blank?

    body, oversized = read_body(request)
    return unauthorized_response("request body exceeds #{MAX_BODY_BYTES} bytes (site_id=#{site_id})") if oversized

    site = Site.find_by(id: site_id)
    unless site && valid_signature?(body, site.api_key, api_key_sig)
      return unauthorized_response("signature verification failed (site_id=#{site_id})")
    end

    @app.call(env)
  end

  def valid_signature?(body, api_key, provided_sig)
    expected_sig = OpenSSL::HMAC.hexdigest('SHA256', api_key, body)
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
    Rails.logger.warn("ApiSignatureVerification: #{log_reason}")

    [
      401,
      { 'Content-Type' => 'application/json' },
      [{ error: 'Unauthorized' }.to_json]
    ]
  end
end
