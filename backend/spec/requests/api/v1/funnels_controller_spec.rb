require 'rails_helper'

RSpec.describe 'Api::V1::FunnelsController', type: :request do
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

  describe 'GET /api/v1/sites/:site_id/funnels' do
    context 'when unauthenticated' do
      it 'returns 401 unauthorized' do
        get "/api/v1/sites/#{site.id}/funnels", headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns 403 forbidden if site belongs to other user' do
        get "/api/v1/sites/#{other_site.id}/funnels", headers: auth_headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 404 not found if site does not exist' do
        get '/api/v1/sites/nonexistent-uuid/funnels', headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end

      it 'returns all funnels for the site' do
        f1 = Funnel.create!(name: 'Funnel 1', site: site, steps: ['/', '/cart'])
        f2 = Funnel.create!(name: 'Funnel 2', site: site, steps: ['/', '/products', '/checkout'])

        get "/api/v1/sites/#{site.id}/funnels", headers: auth_headers

        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        expect(res.size).to eq(2)
        expect(res.pluck('id')).to contain_exactly(f1.id, f2.id)
      end
    end
  end

  describe 'POST /api/v1/sites/:site_id/funnels' do
    let(:valid_params) { { funnel: { name: 'New Funnel', steps: ['/', '/checkout'] } }.to_json }
    let(:invalid_params) { { funnel: { name: 'Invalid Funnel', steps: ['/'] } }.to_json }

    context 'when unauthenticated' do
      it 'returns 401 unauthorized' do
        post "/api/v1/sites/#{site.id}/funnels", params: valid_params, headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns 403 forbidden if site belongs to other user' do
        post "/api/v1/sites/#{other_site.id}/funnels", params: valid_params, headers: auth_headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 404 not found if site does not exist' do
        post '/api/v1/sites/nonexistent-uuid/funnels', params: valid_params, headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end

      it 'creates a new funnel with valid params and returns 201' do
        expect do
          post "/api/v1/sites/#{site.id}/funnels", params: valid_params, headers: auth_headers
        end.to change(Funnel, :count).by(1)

        expect(response).to have_http_status(:created)
        res = response.parsed_body
        expect(res['name']).to eq('New Funnel')
        expect(res['steps']).to eq([{ 'type' => 'url', 'value' => '/' }, { 'type' => 'url', 'value' => '/checkout' }])
        expect(res['site_id']).to eq(site.id)
      end

      it 'creates a funnel from the documented top-level payload without a funnel wrapper' do
        top_level_params = { name: 'Top Level Funnel', steps: ['/', '/checkout'] }.to_json

        expect do
          post "/api/v1/sites/#{site.id}/funnels", params: top_level_params, headers: auth_headers
        end.to change(Funnel, :count).by(1)

        expect(response).to have_http_status(:created)
        res = response.parsed_body
        expect(res['name']).to eq('Top Level Funnel')
        expect(res['steps']).to eq([{ 'type' => 'url', 'value' => '/' }, { 'type' => 'url', 'value' => '/checkout' }])
      end

      it 'creates a funnel from documented object-shaped url and event steps' do
        object_params = {
          funnel: { name: 'Engagement Funnel', steps: [{ type: 'url', value: '/' }, { type: 'event', value: 'click' }] }
        }.to_json

        expect do
          post "/api/v1/sites/#{site.id}/funnels", params: object_params, headers: auth_headers
        end.to change(Funnel, :count).by(1)

        expect(response).to have_http_status(:created)
        res = response.parsed_body
        expect(res['steps']).to eq(
          [{ 'type' => 'url', 'value' => '/' }, { 'type' => 'event', 'value' => 'click' }]
        )
      end

      it 'rejects a steps array that contains a null entry instead of silently dropping it' do
        null_params = { funnel: { name: 'Null Step Funnel', steps: ['/', nil, '/checkout'] } }.to_json

        expect do
          post "/api/v1/sites/#{site.id}/funnels", params: null_params, headers: auth_headers
        end.not_to change(Funnel, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['errors']).to be_present
      end

      it 'returns 422 with validation errors for invalid params' do
        post "/api/v1/sites/#{site.id}/funnels", params: invalid_params, headers: auth_headers

        expect(response).to have_http_status(:unprocessable_content)
        res = response.parsed_body
        expect(res['errors']).to be_present
      end

      it 'returns 400 when the funnel key is a scalar instead of an object' do
        scalar_params = '{"funnel":"abc","steps":["/","/checkout"]}'

        expect do
          post "/api/v1/sites/#{site.id}/funnels", params: scalar_params, headers: auth_headers
        end.not_to change(Funnel, :count)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to be_present
      end

      it 'returns 400 when the funnel key is missing entirely' do
        post "/api/v1/sites/#{site.id}/funnels", params: '{"notfunnel":{}}', headers: auth_headers

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to be_present
      end
    end
  end

  describe 'GET /api/v1/sites/:site_id/funnels/:id' do
    let!(:funnel) { Funnel.create!(name: 'Funnel A', site: site, steps: ['/', '/checkout']) }
    let!(:other_funnel) { Funnel.create!(name: 'Funnel B', site: other_site, steps: ['/', '/cart']) }

    context 'when unauthenticated' do
      it 'returns 401 unauthorized' do
        get "/api/v1/sites/#{site.id}/funnels/#{funnel.id}", headers: unauth_headers
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns 403 forbidden if site belongs to other user' do
        get "/api/v1/sites/#{other_site.id}/funnels/#{funnel.id}", headers: auth_headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 forbidden if funnel belongs to other site' do
        # accessing other_funnel via site
        get "/api/v1/sites/#{site.id}/funnels/#{other_funnel.id}", headers: auth_headers
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 404 not found if funnel does not exist' do
        get "/api/v1/sites/#{site.id}/funnels/nonexistent-funnel-uuid", headers: auth_headers
        expect(response).to have_http_status(:not_found)
      end

      it 'returns funnel analysis results' do
        get "/api/v1/sites/#{site.id}/funnels/#{funnel.id}", headers: auth_headers

        expect(response).to have_http_status(:ok)
        res = response.parsed_body
        expect(res['id']).to eq(funnel.id)
        expect(res['name']).to eq(funnel.name)
        expect(res['completion_rate']).to be_present
        expect(res['steps']).to be_an(Array)
      end

      it 'respects the period query parameter' do
        get "/api/v1/sites/#{site.id}/funnels/#{funnel.id}?period=7d", headers: auth_headers
        expect(response).to have_http_status(:ok)
      end

      it 'returns 422 if period is invalid' do
        get "/api/v1/sites/#{site.id}/funnels/#{funnel.id}?period=invalid", headers: auth_headers
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body['error']).to include('Allowed values: 7d, 30d, 90d')
      end
    end
  end
end
