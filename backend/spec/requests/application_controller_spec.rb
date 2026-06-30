require 'rails_helper'

# We define a dummy controller inside the spec to test ApplicationController behaviors.
class TestApiController < ApplicationController
  def index
    render json: { message: 'Success', current_user: current_user&.as_json }
  end
end

RSpec.describe 'ApplicationController Authentication', type: :request do
  before do
    Rails.application.routes.draw do
      get 'test_api' => 'test_api#index'
    end
  end

  after do
    Rails.application.reload_routes!
  end

  let(:headers) { { 'Accept' => 'application/json' } }

  context 'when unauthenticated' do
    it 'returns unauthorized' do
      get '/test_api', headers: headers
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq({ 'error' => 'Unauthorized' })
    end
  end

  context 'in development environment with DEV_AUTO_LOGIN=true' do
    before do
      allow(Rails.env).to receive(:development?).and_return(true)
      stub_const('ENV', ENV.to_h.merge(
                          'DEV_AUTO_LOGIN' => 'true',
                          'DEV_GOOGLE_SUB' => 'dev_test_sub',
                          'DEV_DISPLAY_NAME' => 'Dev Test User'
                        ))
    end

    context 'when users table does not exist yet' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:users).and_return(false)
      end

      it 'returns unauthorized (safe failure)' do
        get '/test_api', headers: headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when users table exists' do
      let(:mock_user) { double('User', google_sub: 'dev_test_sub', display_name: 'Dev Test User', persisted?: true) }

      before do
        allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:users).and_return(true)
        # Stub User model with dummy class methods to prevent RSpec signature errors
        user_stub = Class.new do
          def self.find_or_create_by(*args); end
        end
        stub_const('User', user_stub)
        allow(User).to receive(:find_or_create_by)
          .with({ google_sub: 'dev_test_sub' }).and_yield(mock_user).and_return(mock_user)
        allow(mock_user).to receive(:display_name=).with('Dev Test User')
        allow(mock_user).to receive(:as_json).and_return({ 'google_sub' => 'dev_test_sub',
                                                           'display_name' => 'Dev Test User' })
      end

      it 'bypasses authentication and returns success with mock user' do
        get '/test_api', headers: headers
        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        expect(res['message']).to eq('Success')
        expect(res['current_user']).to eq({ 'google_sub' => 'dev_test_sub', 'display_name' => 'Dev Test User' })
      end
    end
  end

  context 'with JWT token' do
    let(:secret) { 'test_secret_key' }
    let(:payload) { { 'sub' => 'google_user_123', 'exp' => Time.now.to_i + 3600 } }
    let(:token) { JWT.encode(payload, secret, 'HS256') }

    before do
      stub_const('ENV', ENV.to_h.merge('JWT_SECRET' => secret))
    end

    context 'when users table exists' do
      let(:mock_user) { double('User', google_sub: 'google_user_123') }

      before do
        allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:users).and_return(true)
        user_stub = Class.new do
          def self.find_by(*args); end
        end
        stub_const('User', user_stub)
        allow(User).to receive(:find_by).with(google_sub: 'google_user_123').and_return(mock_user)
        allow(mock_user).to receive(:as_json).and_return({ 'google_sub' => 'google_user_123' })
      end

      it 'returns success when valid token is provided' do
        get '/test_api', headers: headers.merge('Authorization' => "Bearer #{token}")
        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        expect(res['current_user']).to eq({ 'google_sub' => 'google_user_123' })
      end

      it 'returns unauthorized when invalid token is provided' do
        get '/test_api', headers: headers.merge('Authorization' => 'Bearer invalid_token')
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
