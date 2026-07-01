class ApiSignatureVerification
  UUID_REGEX = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

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
    request.path.start_with?('/api/v1/events/') && request.request_method != 'OPTIONS'
  end

  def verify_signature(request, env)
    site_id = request.headers['X-Site-Id']
    api_key_sig = request.headers['X-Api-Key']
    error = find_validation_error(site_id, api_key_sig)
    return unauthorized_response(error) if error

    site = Site.find_by(id: site_id)
    return unauthorized_response('Site not found') unless site
    return unauthorized_response('Invalid API Key signature') unless valid_signature?(request, site.api_key,
                                                                                      api_key_sig)

    @app.call(env)
  end

  def find_validation_error(site_id, api_key_sig)
    if site_id.blank? || api_key_sig.blank?
      'Missing X-Site-Id or X-Api-Key'
    elsif !site_id.match?(UUID_REGEX)
      'Invalid Site ID format'
    end
  end

  def valid_signature?(request, api_key, provided_sig)
    body = read_body(request)
    expected_sig = OpenSSL::HMAC.hexdigest('SHA256', api_key, body)
    ActiveSupport::SecurityUtils.secure_compare(expected_sig, provided_sig)
  end

  def read_body(request)
    return '' unless request.body

    body = request.body.read
    request.body.rewind
    body
  end

  def unauthorized_response(message)
    [
      401,
      { 'Content-Type' => 'application/json' },
      [{ error: "Unauthorized: #{message}" }.to_json]
    ]
  end
end
