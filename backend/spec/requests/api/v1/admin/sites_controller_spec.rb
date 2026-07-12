require 'rails_helper'

RSpec.describe 'Api::V1::Admin::SitesController', type: :request do
  let(:admin_user) { 'admin' }
  let(:admin_pass) { 'password' }

  let(:auth_headers) do
    {
      'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials(admin_user, admin_pass),
      'Accept' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end

  let(:unauth_headers) do
    {
      'Accept' => 'application/json'
    }
  end

  let(:wrong_auth_headers) do
    {
      'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials('wrong', 'wrong'),
      'Accept' => 'application/json'
    }
  end

  let(:user) { User.create!(google_sub: 'user_123', display_name: 'Alice') }
  let!(:site1) { Site.create!(name: 'Site 1', url: 'https://site1.com', user: user) }
  let!(:site2) { Site.create!(name: 'Site 2', url: 'https://site2.com', user: user) }

  before do
    stub_const('ENV', ENV.to_h.merge('ADMIN_USERNAME' => admin_user, 'ADMIN_PASSWORD' => admin_pass))
  end

  describe 'GET /api/v1/admin/sites' do
    context 'when unauthenticated' do
      it 'returns 401' do
        get '/api/v1/admin/sites', headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns 401 with wrong credentials' do
        get '/api/v1/admin/sites', headers: wrong_auth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns all sites' do
        get '/api/v1/admin/sites', headers: auth_headers

        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        expect(res.pluck('id')).to include(site1.id, site2.id)
      end
    end
  end

  describe 'POST /api/v1/admin/sites/:id/reset_ai' do
    context 'when unauthenticated' do
      it 'returns 401' do
        post "/api/v1/admin/sites/#{site1.id}/reset_ai", headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'resets used_count to 0 for current logical JST date' do
        usage_date = 3.hours.ago.to_date
        usage = site1.daily_ai_usages.create!(usage_date: usage_date, used_count: 1)

        post "/api/v1/admin/sites/#{site1.id}/reset_ai", headers: auth_headers

        expect(response).to have_http_status(:ok)
        expect(usage.reload.used_count).to eq(0)
        expect(usage.reset_at).to be_present
      end

      it 'creates a daily_ai_usage record if none existed for today' do
        usage_date = 3.hours.ago.to_date

        expect do
          post "/api/v1/admin/sites/#{site1.id}/reset_ai", headers: auth_headers
        end.to change(DailyAiUsage, :count).by(1)

        expect(response).to have_http_status(:ok)
        usage = site1.daily_ai_usages.find_by(usage_date: usage_date)
        expect(usage.used_count).to eq(0)
        expect(usage.reset_at).to be_present
      end

      it 'returns 404 if site does not exist' do
        post '/api/v1/admin/sites/non_existent_uuid/reset_ai', headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end

      it 'returns 415 and does not reset usage for a form-encoded request' do
        # Regression test: this action is a native POST, so a third-party
        # page could auto-submit a plain HTML <form> against it directly
        # (no Rack::MethodOverride trick even needed) using the admin's
        # browser-cached Basic Auth credentials. A <form> can only send
        # application/x-www-form-urlencoded or multipart/form-data, never
        # JSON, so requiring JSON here closes that path.
        usage_date = 3.hours.ago.to_date
        usage = site1.daily_ai_usages.create!(usage_date: usage_date, used_count: 1)
        form_headers = auth_headers.merge('Content-Type' => 'application/x-www-form-urlencoded')

        post "/api/v1/admin/sites/#{site1.id}/reset_ai", headers: form_headers

        expect(response).to have_http_status(:unsupported_media_type)
        expect(usage.reload.used_count).to eq(1)
      end
    end
  end
end
