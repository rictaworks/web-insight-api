require 'rails_helper'

RSpec.describe ApiSignatureVerification, type: :middleware do
  include ActiveSupport::Testing::TimeHelpers

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

  def sign(api_key, timestamp, body)
    OpenSSL::HMAC.hexdigest('SHA256', api_key, "#{timestamp}.#{body}")
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
    let(:now) { 1_700_000_000 }

    before { travel_to Time.at(now) }
    after { travel_back }

    it 'returns a generic 401 if X-Site-Id is missing' do
      status, _, body = make_request(
        '/api/v1/events/collect',
        { 'HTTP_X_API_KEY' => 'some_sig', 'HTTP_X_TIMESTAMP' => now.to_s },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if X-Api-Key is missing' do
      status, _, body = make_request(
        '/api/v1/events/collect',
        { 'HTTP_X_SITE_ID' => site.id, 'HTTP_X_TIMESTAMP' => now.to_s },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if X-Timestamp is missing' do
      correct_sig = sign(site.api_key, now, body_content)
      status, _, body = make_request(
        '/api/v1/events/collect',
        { 'HTTP_X_SITE_ID' => site.id, 'HTTP_X_API_KEY' => correct_sig },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if X-Timestamp is not a valid integer' do
      status, _, body = make_request(
        '/api/v1/events/collect',
        { 'HTTP_X_SITE_ID' => site.id, 'HTTP_X_API_KEY' => 'sig', 'HTTP_X_TIMESTAMP' => 'not-a-number' },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if X-Timestamp is older than the allowed tolerance' do
      old_timestamp = now - (ApiSignatureVerification::TIMESTAMP_TOLERANCE_SECONDS + 1)
      correct_sig = sign(site.api_key, old_timestamp, body_content)
      status, _, body = make_request(
        '/api/v1/events/collect',
        { 'HTTP_X_SITE_ID' => site.id, 'HTTP_X_API_KEY' => correct_sig, 'HTTP_X_TIMESTAMP' => old_timestamp.to_s },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if X-Timestamp is further in the future than the allowed tolerance' do
      future_timestamp = now + (ApiSignatureVerification::TIMESTAMP_TOLERANCE_SECONDS + 1)
      correct_sig = sign(site.api_key, future_timestamp, body_content)
      status, _, body = make_request(
        '/api/v1/events/collect',
        { 'HTTP_X_SITE_ID' => site.id, 'HTTP_X_API_KEY' => correct_sig, 'HTTP_X_TIMESTAMP' => future_timestamp.to_s },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns the same generic 401 message for an unknown site as for a bad signature' do
      other_uuid = SecureRandom.uuid
      status, _, body = make_request(
        '/api/v1/events/collect',
        { 'HTTP_X_SITE_ID' => other_uuid, 'HTTP_X_API_KEY' => 'sig', 'HTTP_X_TIMESTAMP' => now.to_s },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if signature does not match' do
      status, _, body = make_request(
        '/api/v1/events/collect',
        { 'HTTP_X_SITE_ID' => site.id, 'HTTP_X_API_KEY' => 'wrong_sig', 'HTTP_X_TIMESTAMP' => now.to_s },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if the signature was computed without the timestamp (old scheme replay)' do
      stale_scheme_sig = OpenSSL::HMAC.hexdigest('SHA256', site.api_key, body_content)
      status, _, body = make_request(
        '/api/v1/events/collect',
        { 'HTTP_X_SITE_ID' => site.id, 'HTTP_X_API_KEY' => stale_scheme_sig, 'HTTP_X_TIMESTAMP' => now.to_s },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if the request body exceeds the 32KB limit' do
      oversized_body = { event_type: 'pageview', page_url: '/', padding: 'a' * 33_000 }.to_json
      sig = sign(site.api_key, now, oversized_body)

      status, _, body = make_request(
        '/api/v1/events/collect',
        { 'HTTP_X_SITE_ID' => site.id, 'HTTP_X_API_KEY' => sig, 'HTTP_X_TIMESTAMP' => now.to_s },
        oversized_body
      )
      expect_unauthorized(status, body)
    end

    it 'returns 200 and passes request if signature and timestamp are valid' do
      correct_sig = sign(site.api_key, now, body_content)

      status, _, body = make_request(
        '/api/v1/events/collect',
        { 'HTTP_X_SITE_ID' => site.id, 'HTTP_X_API_KEY' => correct_sig, 'HTTP_X_TIMESTAMP' => now.to_s },
        body_content
      )
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end

    it 'returns 200 for a timestamp within the allowed tolerance boundary' do
      boundary_timestamp = now - ApiSignatureVerification::TIMESTAMP_TOLERANCE_SECONDS
      correct_sig = sign(site.api_key, boundary_timestamp, body_content)

      status, _, body = make_request(
        '/api/v1/events/collect',
        { 'HTTP_X_SITE_ID' => site.id, 'HTTP_X_API_KEY' => correct_sig, 'HTTP_X_TIMESTAMP' => boundary_timestamp.to_s },
        body_content
      )
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end
  end
end
