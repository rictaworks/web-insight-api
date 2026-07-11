require 'rails_helper'

RSpec.describe 'Api::V1::Admin::UsersController', type: :request do
  let(:admin_user) { 'admin' }
  let(:admin_pass) { 'password' }

  let(:auth_headers) do
    {
      'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials(admin_user, admin_pass),
      'Accept' => 'application/json'
    }
  end

  let(:unauth_headers) do
    {
      'Accept' => 'application/json'
    }
  end

  let!(:user1) { User.create!(google_sub: 'user_1', display_name: 'Alice') }
  let!(:user2) { User.create!(google_sub: 'user_2', display_name: 'Bob') }

  before do
    stub_const('ENV', ENV.to_h.merge('ADMIN_USERNAME' => admin_user, 'ADMIN_PASSWORD' => admin_pass))
  end

  describe 'GET /api/v1/admin/users' do
    context 'when unauthenticated' do
      it 'returns 401' do
        get '/api/v1/admin/users', headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns all users' do
        get '/api/v1/admin/users', headers: auth_headers

        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        expect(res.pluck('id')).to include(user1.id, user2.id)
      end
    end
  end

  describe 'GET /api/v1/admin/users/:id' do
    context 'when unauthenticated' do
      it 'returns 401' do
        get "/api/v1/admin/users/#{user1.id}", headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns user details' do
        get "/api/v1/admin/users/#{user1.id}", headers: auth_headers

        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        expect(res['id']).to eq(user1.id)
        expect(res['display_name']).to eq('Alice')
      end

      it 'returns 404 if user not found' do
        get '/api/v1/admin/users/non_existent_uuid', headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
