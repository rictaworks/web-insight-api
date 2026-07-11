require 'rails_helper'

RSpec.describe 'Api::V1::AlertRulesController', type: :request do
  let(:jwt_secret) { 'test_jwt_secret_key_12345' }
  let(:user) { User.create!(google_sub: 'user_123', display_name: 'Alice') }
  let(:other_user) { User.create!(google_sub: 'user_456', display_name: 'Bob') }
  let(:site) { Site.create!(name: 'Alice Site', url: 'https://alicesite.com', user: user) }
  let(:other_site) { Site.create!(name: 'Bob Site', url: 'https://bobsite.com', user: other_user) }

  let(:token) do
    payload = { sub: user.google_sub, exp: Time.now.to_i + 3600 }
    JWT.encode(payload, jwt_secret, 'HS256')
  end

  let(:auth_headers) do
    {
      'Authorization' => "Bearer #{token}",
      'Accept' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end

  let(:unauth_headers) do
    {
      'Accept' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end

  before do
    stub_const('ENV', ENV.to_h.merge('JWT_SECRET' => jwt_secret))
  end

  describe 'GET /api/v1/sites/:site_id/alert_rules' do
    context 'when unauthenticated' do
      it 'returns 401 unauthorized' do
        get "/api/v1/sites/#{site.id}/alert_rules", headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns 403 forbidden if site belongs to other user' do
        get "/api/v1/sites/#{other_site.id}/alert_rules", headers: auth_headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 404 not found if site does not exist' do
        get '/api/v1/sites/nonexistent-uuid/alert_rules', headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end

      it 'returns all alert rules for the site' do
        r1 = AlertRule.create!(site: site, metric: 'pv', condition: 'above', threshold: 100.0)
        r2 = AlertRule.create!(site: site, metric: 'bounce_rate', condition: 'above', threshold: 80.0)

        get "/api/v1/sites/#{site.id}/alert_rules", headers: auth_headers

        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        expect(res.size).to eq(2)
        expect(res.pluck('id')).to contain_exactly(r1.id, r2.id)
      end
    end
  end

  describe 'POST /api/v1/sites/:site_id/alert_rules' do
    let(:valid_params) do
      {
        alert_rule: {
          metric: 'pv',
          condition: 'above',
          threshold: 150.0,
          cooldown_min: 30
        }
      }.to_json
    end

    let(:invalid_params) do
      {
        alert_rule: {
          metric: 'invalid_metric',
          condition: 'above',
          threshold: 150.0
        }
      }.to_json
    end

    context 'when unauthenticated' do
      it 'returns 401 unauthorized' do
        post "/api/v1/sites/#{site.id}/alert_rules", params: valid_params, headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns 403 forbidden if site belongs to other user' do
        post "/api/v1/sites/#{other_site.id}/alert_rules", params: valid_params, headers: auth_headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 404 not found if site does not exist' do
        post '/api/v1/sites/nonexistent-uuid/alert_rules', params: valid_params, headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end

      it 'creates a new alert rule with valid params and returns 201' do
        expect do
          post "/api/v1/sites/#{site.id}/alert_rules", params: valid_params, headers: auth_headers
        end.to change(AlertRule, :count).by(1)

        expect(response).to have_http_status(:created)
        res = response.parsed_body
        expect(res['metric']).to eq('pv')
        expect(res['condition']).to eq('above')
        expect(res['threshold'].to_f).to eq(150.0)
        expect(res['cooldown_min']).to eq(30)
        expect(res['site_id']).to eq(site.id)
      end

      it 'returns 422 with validation errors for invalid params' do
        post "/api/v1/sites/#{site.id}/alert_rules", params: invalid_params, headers: auth_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['errors']).to be_present
      end

      it 'returns 422 instead of a DB error when threshold exceeds the decimal(12,4) column range' do
        out_of_range_params = {
          alert_rule: {
            metric: 'pv',
            condition: 'above',
            threshold: 100_000_000.0,
            cooldown_min: 30
          }
        }.to_json

        post "/api/v1/sites/#{site.id}/alert_rules", params: out_of_range_params, headers: auth_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['errors']).to be_present
      end

      it 'returns 400 when the alert_rule key is a scalar instead of an object' do
        scalar_params = '{"alert_rule":"abc"}'

        expect do
          post "/api/v1/sites/#{site.id}/alert_rules", params: scalar_params, headers: auth_headers
        end.not_to change(AlertRule, :count)

        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe 'PUT /api/v1/sites/:site_id/alert_rules/:id' do
    let!(:rule) { AlertRule.create!(site: site, metric: 'pv', condition: 'above', threshold: 100.0) }
    let!(:other_rule) { AlertRule.create!(site: other_site, metric: 'pv', condition: 'above', threshold: 100.0) }

    let(:update_params) do
      {
        alert_rule: {
          threshold: 200.0,
          cooldown_min: 45
        }
      }.to_json
    end

    context 'when unauthenticated' do
      it 'returns 401 unauthorized' do
        put "/api/v1/sites/#{site.id}/alert_rules/#{rule.id}", params: update_params, headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns 403 forbidden if site belongs to other user' do
        put "/api/v1/sites/#{other_site.id}/alert_rules/#{rule.id}", params: update_params, headers: auth_headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 forbidden if rule belongs to other site' do
        put "/api/v1/sites/#{site.id}/alert_rules/#{other_rule.id}", params: update_params, headers: auth_headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 404 not found if rule does not exist' do
        put "/api/v1/sites/#{site.id}/alert_rules/nonexistent-rule-uuid", params: update_params, headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end

      it 'updates the alert rule and returns 200' do
        put "/api/v1/sites/#{site.id}/alert_rules/#{rule.id}", params: update_params, headers: auth_headers

        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        expect(res['threshold'].to_f).to eq(200.0)
        expect(res['cooldown_min']).to eq(45)
        expect(rule.reload.threshold.to_f).to eq(200.0)
        expect(rule.reload.cooldown_min).to eq(45)
      end

      it 'returns 422 with validation errors for invalid update params' do
        invalid_update = { alert_rule: { metric: 'invalid_metric' } }.to_json
        put "/api/v1/sites/#{site.id}/alert_rules/#{rule.id}", params: invalid_update, headers: auth_headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['errors']).to be_present
      end
    end
  end
end
