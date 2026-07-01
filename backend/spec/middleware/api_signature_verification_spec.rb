require 'rails_helper'

RSpec.describe ApiSignatureVerification, type: :middleware do
  let(:app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] } }
  let(:middleware) { ApiSignatureVerification.new(app) }
  let(:user) { User.create!(google_sub: 'sub_test', display_name: 'Test User') }
  let(:site) do
    Site.create!(name: 'Test Site', url: 'https://example.com', user: user)
  end

  def make_request(path, headers = {}, body = '', method = 'POST')
    env = Rack::MockRequest.env_for(path, headers.merge(method: method, input: body))
    middleware.call(env)
  end

  def expect_unauthorized(status, body)
    expect(status).to eq(401)
    expect(JSON.parse(body.first)['error']).to eq('Unauthorized')
  end

  describe 'path matching' do
    it 'bypasses verification for non-events paths' do
      status, _, body = make_request('/api/v1/auth/google')
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end

    it 'applies verification for events sub-paths' do
      status, _, body = make_request('/api/v1/events/collect')
      expect_unauthorized(status, body)
    end

    it 'applies verification for the exact events path with no trailing segment' do
      status, _, body = make_request('/api/v1/events')
      expect_unauthorized(status, body)
    end

    it 'bypasses verification for OPTIONS requests to events paths' do
      status, _, body = make_request('/api/v1/events/collect', {}, '', 'OPTIONS')
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end
  end

  describe 'signature verification' do
    let(:body_content) { { event_type: 'pageview', page_url: '/' }.to_json }

    it 'returns a generic 401 if X-Site-Id is missing' do
      status, _, body = make_request('/api/v1/events/collect', { 'HTTP_X_API_KEY' => 'some_sig' }, body_content)
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if X-Api-Key is missing' do
      status, _, body = make_request('/api/v1/events/collect', { 'HTTP_X_SITE_ID' => site.id }, body_content)
      expect_unauthorized(status, body)
    end

    it 'returns the same generic 401 message for an unknown site as for a bad signature' do
      other_uuid = SecureRandom.uuid
      status, _, body = make_request('/api/v1/events/collect',
                                     { 'HTTP_X_SITE_ID' => other_uuid, 'HTTP_X_API_KEY' => 'sig' }, body_content)
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if signature does not match' do
      status, _, body = make_request('/api/v1/events/collect',
                                     { 'HTTP_X_SITE_ID' => site.id, 'HTTP_X_API_KEY' => 'wrong_sig' }, body_content)
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if the request body exceeds the 32KB limit' do
      oversized_body = { event_type: 'pageview', page_url: '/', padding: 'a' * 33_000 }.to_json
      key = site.api_key
      sig = OpenSSL::HMAC.hexdigest('SHA256', key, oversized_body)

      status, _, body = make_request(
        '/api/v1/events/collect',
        { 'HTTP_X_SITE_ID' => site.id, 'HTTP_X_API_KEY' => sig },
        oversized_body
      )
      expect_unauthorized(status, body)
    end

    it 'returns 200 and passes request if signature is valid' do
      key = site.api_key
      correct_sig = OpenSSL::HMAC.hexdigest('SHA256', key, body_content)

      status, _, body = make_request(
        '/api/v1/events/collect',
        { 'HTTP_X_SITE_ID' => site.id, 'HTTP_X_API_KEY' => correct_sig },
        body_content
      )
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end
  end
end
