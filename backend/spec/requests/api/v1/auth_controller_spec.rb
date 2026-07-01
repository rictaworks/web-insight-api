require 'rails_helper'

RSpec.describe 'Api::V1::AuthController', type: :request do
  let(:headers) { { 'Accept' => 'application/json' } }
  let(:jwt_secret) { 'test_jwt_secret_key_12345' }

  before do
    stub_const('ENV', ENV.to_h.merge(
                        'JWT_SECRET' => jwt_secret,
                        'GOOGLE_OAUTH_CLIENT_ID' => 'test_client_id.apps.googleusercontent.com',
                        'GOOGLE_OAUTH_CLIENT_SECRET' => 'test_client_secret'
                      ))
  end

  describe 'POST /api/v1/auth/google' do
    context 'when DEV_AUTO_LOGIN is true and Rails.env is development' do
      before do
        allow(Rails.env).to receive(:development?).and_return(true)
        stub_const('ENV', ENV.to_h.merge(
                            'DEV_AUTO_LOGIN' => 'true',
                            'DEV_GOOGLE_SUB' => 'dev_test_sub_999',
                            'DEV_DISPLAY_NAME' => 'Dev Test User 999'
                          ))
      end

      it 'automatically logs in the development mock user' do
        post '/api/v1/auth/google', headers: headers

        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        expect(res['token']).to be_present
        expect(res['user']['display_name']).to eq('Dev Test User 999')

        # Verify issued JWT token
        decoded = JWT.decode(res['token'], jwt_secret, true, { algorithm: 'HS256' })
        expect(decoded[0]['sub']).to eq('dev_test_sub_999')
        expect(decoded[0]['exp']).to be > Time.now.to_i
      end
    end

    context 'when DEV_AUTO_LOGIN is not true' do
      before do
        stub_const('ENV', ENV.to_h.merge('DEV_AUTO_LOGIN' => 'false'))
      end

      it 'returns bad request if auth_code is missing' do
        post '/api/v1/auth/google', headers: headers

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to eq('auth_code is required')
      end

      context 'with auth_code provided' do
        let(:auth_code) { 'valid_google_auth_code' }
        let(:id_token) { 'valid_google_id_token' }

        context 'when Google OAuth token exchange fails' do
          before do
            mock_response = double('Net::HTTPResponse', code: '400', body: '{"error": "invalid_grant"}')
            allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
            allow(Net::HTTP).to receive(:post_form).and_return(mock_response)
          end

          it 'returns unauthorized' do
            post '/api/v1/auth/google', params: { auth_code: auth_code }, headers: headers

            expect(response).to have_http_status(:unauthorized)
            expect(response.parsed_body['error']).to eq('Invalid auth_code or failed to exchange tokens')
          end
        end

        context 'when Google OAuth token exchange succeeds' do
          before do
            mock_response = double('Net::HTTPResponse', code: '200', body: JSON.generate({ id_token: id_token }))
            allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
            allow(Net::HTTP).to receive(:post_form).and_return(mock_response)
          end

          context 'when ID token verification fails' do
            before do
              mock_validator = instance_double(GoogleIDToken::Validator)
              allow(Api::V1::AuthController).to receive(:google_id_token_validator).and_return(mock_validator)
              allow(mock_validator).to receive(:check).with(id_token, 'test_client_id.apps.googleusercontent.com')
                                                      .and_raise(GoogleIDToken::ValidationError.new('Token expired'))
            end

            it 'returns unauthorized' do
              post '/api/v1/auth/google', params: { auth_code: auth_code }, headers: headers

              expect(response).to have_http_status(:unauthorized)
              expect(response.parsed_body['error']).to eq('Invalid Google ID token payload')
            end
          end

          context 'when ID token verification succeeds' do
            let(:google_sub) { 'google_sub_123456789' }
            let(:google_name) { 'Alice Smith' }

            before do
              mock_validator = instance_double(GoogleIDToken::Validator)
              allow(Api::V1::AuthController).to receive(:google_id_token_validator).and_return(mock_validator)
              client_id = 'test_client_id.apps.googleusercontent.com'
              payload = { 'sub' => google_sub, 'name' => google_name, 'email' => 'alice@example.com' }
              allow(mock_validator).to receive(:check).with(id_token, client_id).and_return(payload)
            end

            it 'creates a new user and issues a JWT token' do
              expect do
                post '/api/v1/auth/google', params: { auth_code: auth_code }, headers: headers
              end.to change(User, :count).by(1)

              expect(response).to have_http_status(:ok)
              res = response.parsed_body
              expect(res['token']).to be_present
              expect(res['user']['display_name']).to eq(google_name)

              user = User.find_by(google_sub: google_sub)
              expect(user).to be_present
              expect(user.display_name).to eq(google_name)

              # Verify issued JWT token
              decoded = JWT.decode(res['token'], jwt_secret, true, { algorithm: 'HS256' })
              expect(decoded[0]['sub']).to eq(google_sub)
              expect(decoded[0]['exp']).to be > Time.now.to_i
            end

            it 'updates the display name if it changed' do
              # Create existing user with old name
              existing_user = User.create!(google_sub: google_sub, display_name: 'Alice OldName')

              expect do
                post '/api/v1/auth/google', params: { auth_code: auth_code }, headers: headers
              end.not_to change(User, :count)

              expect(response).to have_http_status(:ok)
              res = response.parsed_body
              expect(res['user']['display_name']).to eq(google_name)

              existing_user.reload
              expect(existing_user.display_name).to eq(google_name)
            end
          end
        end
      end
    end
  end
end
