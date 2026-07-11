require 'rails_helper'

RSpec.describe 'Api::V1::SitesController', type: :request do
  let(:jwt_secret) { 'test_jwt_secret_key_12345' }
  let(:user) { User.create!(google_sub: 'user_123', display_name: 'Alice') }
  let(:other_user) { User.create!(google_sub: 'user_456', display_name: 'Bob') }

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

  describe 'GET /api/v1/sites' do
    context 'when unauthenticated' do
      it 'returns 401 unauthorized' do
        get '/api/v1/sites', headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns user\'s sites' do
        site1 = Site.create!(name: 'Site 1', url: 'https://site1.com', user: user)
        site2 = Site.create!(name: 'Site 2', url: 'https://site2.com', user: user)
        # Site for other user
        Site.create!(name: 'Other Site', url: 'https://other.com', user: other_user)

        get '/api/v1/sites', headers: auth_headers

        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        expect(res.size).to eq(2)
        expect(res.pluck('id')).to contain_exactly(site1.id, site2.id)
      end
    end
  end

  describe 'POST /api/v1/sites' do
    context 'when unauthenticated' do
      it 'returns 401 unauthorized' do
        post '/api/v1/sites', params: { site: { name: 'New Site', url: 'https://new.com' } }.to_json,
                              headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      context 'with valid params' do
        it 'creates a new site and returns 201' do
          expect do
            post '/api/v1/sites', params: { site: { name: 'New Site', url: 'https://new.com' } }.to_json,
                                  headers: auth_headers
          end.to change(Site, :count).by(1)

          expect(response).to have_http_status(:created)
          res = response.parsed_body
          expect(res['name']).to eq('New Site')
          expect(res['url']).to eq('https://new.com')
          expect(res['api_key']).to be_present
          expect(res['verify_token']).to be_present
          expect(res['verified']).to be false
        end
      end

      context 'with invalid params' do
        it 'returns 422 unprocessable entity' do
          post '/api/v1/sites', params: { site: { name: '', url: '' } }.to_json, headers: auth_headers

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['errors']).to be_present
        end
      end

      context 'with a malformed payload shape' do
        it 'returns 400 when the site key is a scalar instead of an object' do
          expect do
            post '/api/v1/sites', params: '{"site":"abc"}', headers: auth_headers
          end.not_to change(Site, :count)

          expect(response).to have_http_status(:bad_request)
          expect(response.parsed_body['error']).to be_present
        end

        it 'returns 400 when the site key is missing entirely' do
          post '/api/v1/sites', params: '{"notsite":{}}', headers: auth_headers

          expect(response).to have_http_status(:bad_request)
          expect(response.parsed_body['error']).to be_present
        end
      end

      context 'when site limit is reached' do
        before do
          10.times do |i|
            Site.create!(name: "Site #{i}", url: "https://site#{i}.com", user: user)
          end
        end

        it 'refuses to create the 11th site and returns 422' do
          expect do
            post '/api/v1/sites', params: { site: { name: '11th Site', url: 'https://site11.com' } }.to_json,
                                  headers: auth_headers
          end.not_to change(Site, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to include('Maximum site limit reached')
        end
      end
    end
  end

  describe 'GET /api/v1/sites/:id' do
    let!(:my_site) { Site.create!(name: 'My Site', url: 'https://my.com', user: user) }
    let!(:other_site) { Site.create!(name: 'Other Site', url: 'https://other.com', user: other_user) }

    context 'when unauthenticated' do
      it 'returns 401' do
        get "/api/v1/sites/#{my_site.id}", headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns site details if it belongs to current user' do
        get "/api/v1/sites/#{my_site.id}", headers: auth_headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['id']).to eq(my_site.id)
      end

      it 'returns 403 forbidden if site belongs to other user' do
        get "/api/v1/sites/#{other_site.id}", headers: auth_headers

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body['error']).to eq('Forbidden')
      end

      it 'returns 404 not found if site does not exist' do
        get '/api/v1/sites/non_existent_uuid', headers: auth_headers

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['error']).to eq('Not Found')
      end
    end
  end

  describe 'GET /api/v1/sites/:id/snippet' do
    let!(:my_site) { Site.create!(name: 'My Site', url: 'https://my.com', user: user) }
    let!(:other_site) { Site.create!(name: 'Other Site', url: 'https://other.com', user: other_user) }

    context 'when unauthenticated' do
      it 'returns 401' do
        get "/api/v1/sites/#{my_site.id}/snippet", headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns snippet code if site belongs to current user' do
        get "/api/v1/sites/#{my_site.id}/snippet", headers: auth_headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['snippet']).to be_a(String)
        expect(response.parsed_body['snippet']).to include(my_site.id)
      end

      it 'returns 403 forbidden if site belongs to other user' do
        get "/api/v1/sites/#{other_site.id}/snippet", headers: auth_headers

        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 404 not found if site does not exist' do
        get '/api/v1/sites/non_existent_uuid/snippet', headers: auth_headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/sites/:id/pageviews' do
    let!(:my_site) { Site.create!(name: 'My Site', url: 'https://my.com', user: user) }
    let!(:other_site) { Site.create!(name: 'Other Site', url: 'https://other.com', user: other_user) }

    context 'when unauthenticated' do
      it 'returns 401' do
        get "/api/v1/sites/#{my_site.id}/pageviews?period=7d&axis=day", headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns 403 forbidden if site belongs to other user' do
        get "/api/v1/sites/#{other_site.id}/pageviews?period=7d&axis=day", headers: auth_headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 404 not found if site does not exist' do
        get '/api/v1/sites/non_existent_uuid/pageviews?period=7d&axis=day', headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end

      it 'returns 422 if period is missing or invalid' do
        get "/api/v1/sites/#{my_site.id}/pageviews?axis=day", headers: auth_headers
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('Invalid or missing period')

        get "/api/v1/sites/#{my_site.id}/pageviews?period=invalid&axis=day", headers: auth_headers
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns 422 if axis is missing or invalid' do
        get "/api/v1/sites/#{my_site.id}/pageviews?period=7d", headers: auth_headers
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('Invalid or missing axis')

        get "/api/v1/sites/#{my_site.id}/pageviews?period=7d&axis=invalid", headers: auth_headers
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns 200 and pageviews data if site belongs to user and parameters are valid' do
        # Create some test events
        session = Session.create!(site: my_site, fingerprint: 'fp1', started_at: 1.day.ago)
        Event.create!(site: my_site, session: session, event_type: 'pageview', occurred_at: 1.day.ago)

        get "/api/v1/sites/#{my_site.id}/pageviews?period=7d&axis=day", headers: auth_headers

        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        expect(res['totals']).to be_present
        expect(res['totals']['pv']).to eq(1)
        expect(res['change_rates']).to be_present
        expect(res['series']).to be_an(Array)
        expect(res['series'].size).to eq(7)
      end
    end
  end

  describe 'GET /api/v1/sites/:id/heatmap' do
    let!(:my_site) { Site.create!(name: 'My Site', url: 'https://my.com', user: user) }
    let!(:other_site) { Site.create!(name: 'Other Site', url: 'https://other.com', user: other_user) }

    context 'when unauthenticated' do
      it 'returns 401 unauthorized' do
        get "/api/v1/sites/#{my_site.id}/heatmap?url=https://my.com/&viewport=desktop", headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns 403 forbidden if site does not belong to user' do
        get "/api/v1/sites/#{other_site.id}/heatmap?url=https://other.com/&viewport=desktop", headers: auth_headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 404 not found if site does not exist' do
        get '/api/v1/sites/non_existent_uuid/heatmap?url=https://my.com/&viewport=desktop', headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end

      it 'returns 422 if url is missing' do
        get "/api/v1/sites/#{my_site.id}/heatmap?viewport=desktop", headers: auth_headers
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error']).to include('Invalid or missing url')
      end

      it 'returns 422 (not 500) if url is not a string (parameter pollution)' do
        # ?url[]=https://my.com/ makes Rails pass an Array; it must be rejected,
        # not propagated into URI.parse / string matching.
        get "/api/v1/sites/#{my_site.id}/heatmap?url[]=https://my.com/&viewport=desktop", headers: auth_headers
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error']).to include('Invalid or missing url')
      end

      it 'returns 422 if viewport is missing or invalid' do
        get "/api/v1/sites/#{my_site.id}/heatmap?url=https://my.com/", headers: auth_headers
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error']).to include('Invalid or missing viewport')

        get "/api/v1/sites/#{my_site.id}/heatmap?url=https://my.com/&viewport=invalid", headers: auth_headers
        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns 200 and heatmap data if parameters are valid' do
        get "/api/v1/sites/#{my_site.id}/heatmap?url=https://my.com/&viewport=desktop", headers: auth_headers

        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        expect(res['grid']).to be_an(Array)
        expect(res['grid'].size).to eq(20)
        expect(res['max_count']).to eq(0)
      end
    end
  end

  describe 'GET /api/v1/sites/:id/performance' do
    let!(:my_site) { Site.create!(name: 'My Site', url: 'https://my.com', user: user) }
    let!(:other_site) { Site.create!(name: 'Other Site', url: 'https://other.com', user: other_user) }

    context 'when unauthenticated' do
      it 'returns 401 unauthorized' do
        get "/api/v1/sites/#{my_site.id}/performance?period=7d&percentile=p75", headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns 403 forbidden if site belongs to other user' do
        get "/api/v1/sites/#{other_site.id}/performance?period=7d&percentile=p75", headers: auth_headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 404 not found if site does not exist' do
        get '/api/v1/sites/non_existent_uuid/performance?period=7d&percentile=p75', headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end

      it 'returns 422 if period is missing or invalid' do
        get "/api/v1/sites/#{my_site.id}/performance?percentile=p75", headers: auth_headers
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error']).to include('Invalid or missing period')

        get "/api/v1/sites/#{my_site.id}/performance?period=invalid&percentile=p75", headers: auth_headers
        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns 422 if percentile is missing or invalid' do
        get "/api/v1/sites/#{my_site.id}/performance?period=7d", headers: auth_headers
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error']).to include('Invalid or missing percentile')

        get "/api/v1/sites/#{my_site.id}/performance?period=7d&percentile=invalid", headers: auth_headers
        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns 200 and performance data if parameters are valid' do
        session = Session.create!(site: my_site, fingerprint: 'fp1', started_at: 1.day.ago)
        WebVital.create!(
          site: my_site,
          session: session,
          page_url: 'https://my.com/home',
          lcp_ms: 2500,
          fid_ms: 100,
          cls_score: 0.1,
          ttfb_ms: 800,
          fcp_ms: 1800,
          created_at: 1.day.ago
        )

        get "/api/v1/sites/#{my_site.id}/performance?period=7d&percentile=p75", headers: auth_headers

        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        # Values sit exactly on the good/needs_improvement threshold, which the
        # Web Vitals spec classifies as "good" (upper bound inclusive).
        expect(res['lcp']).to be_present
        expect(res['lcp']['value']).to eq(2500)
        expect(res['lcp']['rating']).to eq('good')

        expect(res['fid']['value']).to eq(100)
        expect(res['fid']['rating']).to eq('good')

        expect(res['cls']['value']).to eq(0.1)
        expect(res['cls']['rating']).to eq('good')

        expect(res['ttfb']['value']).to eq(800)
        expect(res['ttfb']['rating']).to eq('good')

        expect(res['fcp']['value']).to eq(1800)
        expect(res['fcp']['rating']).to eq('good')
      end
    end
  end

  describe 'GET /api/v1/sites/:id/retention' do
    let!(:my_site) { Site.create!(name: 'My Site', url: 'https://my.com', user: user) }
    let!(:other_site) { Site.create!(name: 'Other Site', url: 'https://other.com', user: other_user) }

    context 'when unauthenticated' do
      it 'returns 401' do
        get "/api/v1/sites/#{my_site.id}/retention?cohort_unit=week", headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns 403 forbidden if site belongs to other user' do
        get "/api/v1/sites/#{other_site.id}/retention?cohort_unit=week", headers: auth_headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 404 not found if site does not exist' do
        get '/api/v1/sites/non_existent_uuid/retention?cohort_unit=week', headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end

      it 'returns 422 if cohort_unit is missing or invalid' do
        get "/api/v1/sites/#{my_site.id}/retention", headers: auth_headers
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error']).to include('Invalid or missing cohort_unit')

        get "/api/v1/sites/#{my_site.id}/retention?cohort_unit=invalid", headers: auth_headers
        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns 200 and retention data if parameters are valid' do
        # Create a session
        Session.create!(site: my_site, fingerprint: 'fp1', started_at: Time.current)

        get "/api/v1/sites/#{my_site.id}/retention?cohort_unit=week", headers: auth_headers

        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        expect(res['cohort_unit']).to eq('week')
        expect(res['matrix']).to be_present
        expect(res['matrix'].size).to eq(12)
      end
    end
  end

  describe 'POST /api/v1/sites/:id/recommend' do
    let!(:my_site) { Site.create!(name: 'My Site', url: 'https://my.com', user: user) }
    let!(:other_site) { Site.create!(name: 'Other Site', url: 'https://other.com', user: other_user) }

    context 'when unauthenticated' do
      it 'returns 401' do
        post "/api/v1/sites/#{my_site.id}/recommend", headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns 403 forbidden if site belongs to other user' do
        post "/api/v1/sites/#{other_site.id}/recommend", headers: auth_headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 404 not found if site does not exist' do
        post '/api/v1/sites/non_existent_uuid/recommend', headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end

      it 'returns 200 and recommendations if within limit' do
        service_double = instance_double(AiRecommendationService)
        allow(AiRecommendationService).to receive(:new).with(my_site).and_return(service_double)

        recommendations = [
          AiRecommendation.new(site: my_site, category: 'UX', priority: 1, description: 'UX advice',
                               estimated_impact: '高')
        ]
        allow(service_double).to receive(:generate_recommendations).and_return(recommendations)

        post "/api/v1/sites/#{my_site.id}/recommend", headers: auth_headers

        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        expect(res['recommendations'].size).to eq(1)
        expect(res['recommendations'].first['category']).to eq('UX')
      end

      it 'returns 429 too many requests if daily limit is reached' do
        service_double = instance_double(AiRecommendationService)
        allow(AiRecommendationService).to receive(:new).with(my_site).and_return(service_double)
        allow(service_double).to receive(:generate_recommendations)
          .and_raise(AiRecommendationService::LimitExceededError.new('Limit reached'))

        post "/api/v1/sites/#{my_site.id}/recommend", headers: auth_headers

        expect(response).to have_http_status(:too_many_requests)
        expect(response.parsed_body['error']).to eq('Limit reached')
      end

      it 'returns a generic error message without leaking the raw LLM response on failure' do
        # Regression test: LLMError messages embed the raw LLM output (e.g.
        # "Raw content: ..."), which must never reach the client as-is —
        # only a fixed, user-facing message should be rendered, with the
        # detailed error left to the server log.
        service_double = instance_double(AiRecommendationService)
        allow(AiRecommendationService).to receive(:new).with(my_site).and_return(service_double)
        raw_response = '{"recommendations": [{"secret_internal_field": "should not leak"}]}'
        error_message = "Invalid recommendation item from LLM. Raw content: #{raw_response}"
        allow(service_double).to receive(:generate_recommendations)
          .and_raise(AiRecommendationService::LLMError.new(error_message))

        post "/api/v1/sites/#{my_site.id}/recommend", headers: auth_headers

        expect(response).to have_http_status(:internal_server_error)
        expect(response.parsed_body['error']).not_to include('secret_internal_field')
        expect(response.parsed_body['error']).not_to include('Raw content')
      end
    end
  end
end
