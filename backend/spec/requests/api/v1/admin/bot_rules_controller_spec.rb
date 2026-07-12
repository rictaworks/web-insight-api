require 'rails_helper'

RSpec.describe 'Api::V1::Admin::BotRulesController', type: :request do
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
      'Accept' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end

  before do
    stub_const('ENV', ENV.to_h.merge('ADMIN_USERNAME' => admin_user, 'ADMIN_PASSWORD' => admin_pass))
    # db:seed populates default bot rules on a fresh database (see
    # db/seeds.rb), and CI's db:prepare runs it before the suite starts — so
    # these examples cannot assume the table starts empty without clearing it.
    BotRule.delete_all
    Rails.cache.clear
  end

  describe 'PUT /api/v1/admin/bot_rules' do
    context 'when unauthenticated' do
      it 'returns 401' do
        put '/api/v1/admin/bot_rules', params: { keywords: ['testbot'] }.to_json, headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'updates the bot rules and clears cache' do
        BotRule.create!(pattern: 'old_bot')

        # prime the cache
        expect(BotDetector.bot_ua_keywords).to include('old_bot')

        payload = { keywords: ['new_bot', 'another_bot', ''] }

        put '/api/v1/admin/bot_rules', params: payload.to_json, headers: auth_headers

        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        expect(res['keywords']).to contain_exactly('new_bot', 'another_bot')
        expect(BotRule.pluck(:pattern)).to contain_exactly('new_bot', 'another_bot')

        # check that cache was cleared and has new values
        expect(BotDetector.bot_ua_keywords).to contain_exactly('new_bot', 'another_bot')
      end

      it 'returns 422 if keywords parameter is invalid' do
        put '/api/v1/admin/bot_rules', params: { keywords: 'not_an_array' }.to_json, headers: auth_headers
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns 422 and does not clear existing rules if a keyword element is not a string' do
        # Regression test: a table-shaped element like {"pattern":"Googlebot"}
        # must not be silently coerced via to_s and persisted; that would
        # leave bot detection configured with a stringified-hash pattern.
        BotRule.create!(pattern: 'existing_bot')

        payload = { keywords: [{ pattern: 'Googlebot' }] }
        put '/api/v1/admin/bot_rules', params: payload.to_json, headers: auth_headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(BotRule.pluck(:pattern)).to contain_exactly('existing_bot')
      end

      it 'returns 422 and does not clear existing rules if keywords would leave zero rules' do
        # Regression test: an empty rule set would be indistinguishable from a
        # not-yet-seeded table (BotDetector falls back to defaults for that
        # case), so the request must be rejected instead of silently
        # reverting bot detection to the default keyword list.
        BotRule.create!(pattern: 'existing_bot')

        put '/api/v1/admin/bot_rules', params: { keywords: ['', '   '] }.to_json, headers: auth_headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(BotRule.pluck(:pattern)).to contain_exactly('existing_bot')
      end

      it 'returns 415 and leaves rules untouched for a form-encoded request (closes the MethodOverride CSRF path)' do
        # Regression test: Rack::MethodOverride must stay in the app's
        # global middleware stack (RailsAdmin raises at boot otherwise), so
        # without this check, a third-party page could auto-submit a plain
        # HTML <form method="post"> with a hidden _method=put field and
        # keywords[]=..., which Rack rewrites into this PUT action and runs
        # with the admin's browser-cached Basic Auth credentials — no CORS
        # preflight applies to a "simple" form POST. A <form> can only send
        # application/x-www-form-urlencoded or multipart/form-data, never
        # JSON, so requiring JSON here closes that path.
        BotRule.create!(pattern: 'existing_bot')
        form_headers = auth_headers.merge('Content-Type' => 'application/x-www-form-urlencoded')

        put '/api/v1/admin/bot_rules', params: { keywords: ['forged_bot'] }, headers: form_headers

        expect(response).to have_http_status(:unsupported_media_type)
        expect(BotRule.pluck(:pattern)).to contain_exactly('existing_bot')
      end
    end
  end
end
