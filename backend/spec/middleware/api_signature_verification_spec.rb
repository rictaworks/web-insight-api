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

  def rack_header(header_name)
    "HTTP_#{header_name.upcase.tr('-', '_')}"
  end

  let(:site_id_key) { rack_header(ApiSignatureVerification::SITE_ID_HEADER) }
  let(:api_key_key) { rack_header(ApiSignatureVerification::API_KEY_HEADER) }
  let(:timestamp_key) { rack_header(ApiSignatureVerification::TIMESTAMP_HEADER) }

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

    around { |example| travel_to(Time.zone.at(now)) { example.run } }

    it 'returns a generic 401 if X-Site-Id is missing' do
      status, _, body = make_request(
        '/api/v1/events/collect',
        { api_key_key => 'some_sig', timestamp_key => now.to_s },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if X-Api-Key is missing' do
      status, _, body = make_request(
        '/api/v1/events/collect',
        { site_id_key => site.id, timestamp_key => now.to_s },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if X-Timestamp is missing' do
      correct_sig = sign(site.api_key, now, body_content)
      status, _, body = make_request(
        '/api/v1/events/collect',
        { site_id_key => site.id, api_key_key => correct_sig },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if X-Timestamp is not a valid integer' do
      status, _, body = make_request(
        '/api/v1/events/collect',
        { site_id_key => site.id, api_key_key => 'sig', timestamp_key => 'not-a-number' },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'logs a distinct reason for a malformed timestamp vs a stale one' do
      expect(Rails.logger).to receive(:warn).with(/invalid X-Timestamp format/)
      make_request(
        '/api/v1/events/collect',
        { site_id_key => site.id, api_key_key => 'sig', timestamp_key => 'not-a-number' },
        body_content
      )
    end

    it 'treats a zero-padded timestamp as decimal, not octal' do
      zero_padded = format('%011d', now)
      correct_sig = sign(site.api_key, zero_padded, body_content)

      status, _, body = make_request(
        '/api/v1/events/collect',
        { site_id_key => site.id, api_key_key => correct_sig, timestamp_key => zero_padded },
        body_content
      )
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end

    it 'returns a generic 401 if X-Timestamp is older than the allowed tolerance' do
      old_timestamp = now - (ApiSignatureVerification.timestamp_tolerance_seconds + 1)
      correct_sig = sign(site.api_key, old_timestamp, body_content)
      status, _, body = make_request(
        '/api/v1/events/collect',
        { site_id_key => site.id, api_key_key => correct_sig, timestamp_key => old_timestamp.to_s },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if X-Timestamp is further in the future than the allowed tolerance' do
      future_timestamp = now + (ApiSignatureVerification.timestamp_tolerance_seconds + 1)
      correct_sig = sign(site.api_key, future_timestamp, body_content)
      status, _, body = make_request(
        '/api/v1/events/collect',
        { site_id_key => site.id, api_key_key => correct_sig, timestamp_key => future_timestamp.to_s },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns the same generic 401 message for an unknown site as for a bad signature' do
      other_uuid = SecureRandom.uuid
      status, _, body = make_request(
        '/api/v1/events/collect',
        { site_id_key => other_uuid, api_key_key => 'sig', timestamp_key => now.to_s },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if signature does not match' do
      status, _, body = make_request(
        '/api/v1/events/collect',
        { site_id_key => site.id, api_key_key => 'wrong_sig', timestamp_key => now.to_s },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if the signature was computed without the timestamp (old scheme replay)' do
      stale_scheme_sig = OpenSSL::HMAC.hexdigest('SHA256', site.api_key, body_content)
      status, _, body = make_request(
        '/api/v1/events/collect',
        { site_id_key => site.id, api_key_key => stale_scheme_sig, timestamp_key => now.to_s },
        body_content
      )
      expect_unauthorized(status, body)
    end

    it 'returns a generic 401 if the request body exceeds the 32KB limit' do
      oversized_body = { event_type: 'pageview', page_url: '/', padding: 'a' * 33_000 }.to_json
      sig = sign(site.api_key, now, oversized_body)

      status, _, body = make_request(
        '/api/v1/events/collect',
        { site_id_key => site.id, api_key_key => sig, timestamp_key => now.to_s },
        oversized_body
      )
      expect_unauthorized(status, body)
    end

    it 'returns 200 and passes request if signature and timestamp are valid' do
      correct_sig = sign(site.api_key, now, body_content)

      status, _, body = make_request(
        '/api/v1/events/collect',
        { site_id_key => site.id, api_key_key => correct_sig, timestamp_key => now.to_s },
        body_content
      )
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end

    it 'returns 200 for a timestamp within the allowed tolerance boundary' do
      boundary_timestamp = now - ApiSignatureVerification.timestamp_tolerance_seconds
      correct_sig = sign(site.api_key, boundary_timestamp, body_content)

      status, _, body = make_request(
        '/api/v1/events/collect',
        { site_id_key => site.id, api_key_key => correct_sig, timestamp_key => boundary_timestamp.to_s },
        body_content
      )
      expect(status).to eq(200)
      expect(body).to eq(['OK'])
    end
  end

  describe '.timestamp_tolerance_seconds' do
    around do |example|
      original = ENV.fetch('API_TIMESTAMP_TOLERANCE_SECONDS', nil)
      example.run
      if original.nil?
        ENV.delete('API_TIMESTAMP_TOLERANCE_SECONDS')
      else
        ENV['API_TIMESTAMP_TOLERANCE_SECONDS'] = original
      end
    end

    it 'defaults to 300 when the env var is unset' do
      ENV.delete('API_TIMESTAMP_TOLERANCE_SECONDS')
      expect(described_class.timestamp_tolerance_seconds).to eq(300)
    end

    it 'uses the env var value when it is a valid positive integer' do
      ENV['API_TIMESTAMP_TOLERANCE_SECONDS'] = '120'
      expect(described_class.timestamp_tolerance_seconds).to eq(120)
    end

    it 'falls back to the default and warns when the env var is malformed outside production' do
      ENV['API_TIMESTAMP_TOLERANCE_SECONDS'] = 'not-a-number'
      allow(Rails.env).to receive(:production?).and_return(false)
      expect(Rails.logger).to receive(:warn).with(/API_TIMESTAMP_TOLERANCE_SECONDS is invalid/)
      expect(described_class.timestamp_tolerance_seconds).to eq(300)
    end

    it 'raises when the env var is malformed in production' do
      ENV['API_TIMESTAMP_TOLERANCE_SECONDS'] = '0'
      allow(Rails.env).to receive(:production?).and_return(true)
      expect do
        described_class.timestamp_tolerance_seconds
      end.to raise_error(/API_TIMESTAMP_TOLERANCE_SECONDS is invalid/)
    end
  end
end
