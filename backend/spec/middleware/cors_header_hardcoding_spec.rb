require 'rails_helper'

RSpec.describe 'CORS header configuration' do
  let(:cors_source) { Rails.root.join('config/initializers/cors.rb').read }

  it 'references the shared ApiSignatureVerification header constants instead of duplicating literals' do
    expect(cors_source).to include('ApiSignatureVerification::SITE_ID_HEADER')
    expect(cors_source).to include('ApiSignatureVerification::API_KEY_HEADER')
    expect(cors_source).to include('ApiSignatureVerification::TIMESTAMP_HEADER')
  end

  it 'does not hardcode the api signature header names as raw string literals' do
    expect(cors_source).not_to include("\"#{ApiSignatureVerification::SITE_ID_HEADER}\"")
    expect(cors_source).not_to include("\"#{ApiSignatureVerification::API_KEY_HEADER}\"")
    expect(cors_source).not_to include("\"#{ApiSignatureVerification::TIMESTAMP_HEADER}\"")
  end

  it 'actually allows the signature headers for the collect endpoint preflight' do
    env = Rack::MockRequest.env_for(
      '/api/v1/events/collect',
      method: 'OPTIONS',
      'HTTP_ORIGIN' => 'https://visitor-site.example',
      'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'POST',
      'HTTP_ACCESS_CONTROL_REQUEST_HEADERS' => 'X-Timestamp'
    )
    _status, headers, = Rails.application.call(env)

    expect(headers['access-control-allow-headers']).to eq('X-Timestamp')
    expect(headers['access-control-allow-origin']).to eq('*')
  end

  it 'exposes the Date header so browser clients can read it for clock-skew correction on 401s' do
    env = Rack::MockRequest.env_for(
      '/api/v1/events/collect',
      method: 'OPTIONS',
      'HTTP_ORIGIN' => 'https://visitor-site.example',
      'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'POST',
      'HTTP_ACCESS_CONTROL_REQUEST_HEADERS' => 'X-Timestamp'
    )
    _status, headers, = Rails.application.call(env)

    expect(headers['access-control-expose-headers']).to eq('Date')
  end
end
