require 'rails_helper'

RSpec.describe ApiSignatureVerification, type: :middleware do
  let(:app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] } }
  let(:middleware) { ApiSignatureVerification.new(app) }
  let(:user) { User.create!(google_sub: 'sub_test', display_name: 'Test User') }
  # api_key is auto-generated in our target implementation
  let(:site) do
    Site.create!(name: 'Test Site', url: 'https://example.com', user: user)
  end
  def make_request(path, headers = {}, body = '', method = 'POST')
    env = Rack::MockRequest.env_for(path, headers.merge(method: method, input: body))
    middleware.call(env)
  end

  describe 'path matching' do
    it 'bypasses verification for non-events paths' do
      status, _, body = make_request('/api/v1/auth/google')
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end

    it 'applies verification for events paths' do
      status, _, body = make_request('/api/v1/events/collect')
      expect(status).to eq(401)
      expect(JSON.parse(body.first)['error']).to include('Missing X-Site-Id or X-Api-Key')
    end

    it 'bypasses verification for OPTIONS requests to events paths' do
      status, _, body = make_request('/api/v1/events/collect', {}, '', 'OPTIONS')
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end
  end

  describe 'signature verification' do
    let(:body_content) { { event_type: 'pageview', page_url: '/' }.to_json }

    it 'returns 401 if X-Site-Id is missing' do
      status, _, body = make_request('/api/v1/events/collect', { 'HTTP_X_API_KEY' => 'some_sig' }, body_content)
      expect(status).to eq(401)
      expect(JSON.parse(body.first)['error']).to include('Missing X-Site-Id or X-Api-Key')
    end

    it 'returns 401 if X-Api-Key is missing' do
      status, _, body = make_request('/api/v1/events/collect', { 'HTTP_X_SITE_ID' => site.id }, body_content)
      expect(status).to eq(401)
      expect(JSON.parse(body.first)['error']).to include('Missing X-Site-Id or X-Api-Key')
    end

    it 'returns 401 if X-Site-Id format is invalid UUID' do
      status, _, body = make_request('/api/v1/events/collect',
                                     { 'HTTP_X_SITE_ID' => 'invalid-uuid', 'HTTP_X_API_KEY' => 'sig' }, body_content)
      expect(status).to eq(401)
      expect(JSON.parse(body.first)['error']).to include('Invalid Site ID format')
    end

    it 'returns 401 if Site is not found' do
      other_uuid = SecureRandom.uuid
      status, _, body = make_request('/api/v1/events/collect',
                                     { 'HTTP_X_SITE_ID' => other_uuid, 'HTTP_X_API_KEY' => 'sig' }, body_content)
      expect(status).to eq(401)
      expect(JSON.parse(body.first)['error']).to include('Site not found')
    end

    it 'returns 401 if signature does not match' do
      status, _, body = make_request('/api/v1/events/collect',
                                     { 'HTTP_X_SITE_ID' => site.id, 'HTTP_X_API_KEY' => 'wrong_sig' }, body_content)
      expect(status).to eq(401)
      expect(JSON.parse(body.first)['error']).to include('Invalid API Key signature')
    end

    it 'returns 200 and passes request if signature is valid' do
      # Calculate correct HMAC-SHA256 signature
      # In order for site.api_key to be generated, we ensure site is saved.
      # If site.api_key is nil, we mock it or use the auto-generated one.
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
