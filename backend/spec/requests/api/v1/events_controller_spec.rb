require 'rails_helper'

RSpec.describe 'Events Collect API', type: :request do
  let(:user) { User.create!(google_sub: 'sub_test_events', display_name: 'Events Test User') }
  let(:site) { Site.create!(name: 'Test Site', url: 'https://example.com', user: user) }

  def sign(api_key, timestamp, body)
    OpenSSL::HMAC.hexdigest('SHA256', api_key, "#{timestamp}.#{body}")
  end

  def auth_headers(body)
    timestamp = Time.current.to_i
    sig = sign(site.api_key, timestamp, body)
    {
      'X-Site-Id' => site.id,
      'X-Api-Key' => sig,
      'X-Timestamp' => timestamp.to_s,
      'Content-Type' => 'application/json'
    }
  end

  describe 'POST /api/v1/events/collect' do
    let(:valid_payload) do
      {
        event_type: 'pageview',
        page_url: 'https://example.com/home',
        referrer: 'https://google.com',
        user_agent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        recaptcha_token: 'valid_token',
        properties: { key: 'value' }
      }.to_json
    end

    before do
      allow(RecaptchaValidator).to receive(:verify).and_return(true)
    end

    context 'when request is valid' do
      it 'creates a session and an event and returns ok' do
        expect do
          post '/api/v1/events/collect', params: valid_payload, headers: auth_headers(valid_payload)
        end.to change(Event, :count).by(1)
                                    .and change(Session, :count).by(1)

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['status']).to eq('ok')
        expect(json['id']).to be_present

        event = Event.last
        expect(event.event_type).to eq('pageview')
        expect(event.page_url).to eq('https://example.com/home')
        expect(event.referrer).to eq('https://google.com')
        expect(event.user_agent).to eq('Mozilla/5.0 (Windows NT 10.0; Win64; x64)')
        expect(event.is_bot).to be(false)
        expect(event.properties).to eq({ 'key' => 'value' })

        session = Session.last
        expect(session.site_id).to eq(site.id)
        expect(session.is_bot).to be(false)
        expect(session.channel).to eq('organic') # since referrer matches google.
      end

      it 'creates a WebVital record when properties contains Core Web Vitals metrics' do
        payload = {
          event_type: 'pageview',
          page_url: 'https://example.com/home',
          recaptcha_token: 'valid_token',
          properties: {
            lcp_ms: 2500,
            fid_ms: 100,
            cls_score: 0.1,
            ttfb_ms: 800,
            fcp_ms: 1800
          }
        }.to_json

        expect do
          post '/api/v1/events/collect', params: payload, headers: auth_headers(payload)
        end.to change(WebVital, :count).by(1)

        expect(response).to have_http_status(:ok)
        vital = WebVital.last
        expect(vital.site_id).to eq(site.id)
        expect(vital.page_url).to eq('https://example.com/home')
        expect(vital.lcp_ms).to eq(2500)
        expect(vital.fid_ms).to eq(100)
        expect(vital.cls_score).to eq(0.1)
        expect(vital.ttfb_ms).to eq(800)
        expect(vital.fcp_ms).to eq(1800)
      end

      it 'returns 400 and writes nothing when Web Vitals are present but page_url is blank' do
        payload = {
          event_type: 'pageview',
          recaptcha_token: 'valid_token',
          properties: { lcp_ms: 2500 }
        }.to_json

        expect do
          post '/api/v1/events/collect', params: payload, headers: auth_headers(payload)
        end.to change(Event, :count).by(0)
                                    .and change(WebVital, :count).by(0)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to include('page_url is required')
      end

      it 'accepts a custom event without page_url whose property merely shares a vital alias name' do
        # `cls` is a generic Web Vitals alias, but a non-numeric value is not a
        # real metric — extract_vitals ignores it — so it must not trigger the
        # page_url requirement and reject an otherwise valid custom event.
        payload = {
          event_type: 'custom',
          recaptcha_token: 'valid_token',
          properties: { cls: 'variant-b' }
        }.to_json

        expect do
          post '/api/v1/events/collect', params: payload, headers: auth_headers(payload)
        end.to change(Event, :count).by(1)
                                    .and change(WebVital, :count).by(0)

        expect(response).to have_http_status(:ok)
        expect(Event.last.properties).to eq({ 'cls' => 'variant-b' })
      end

      it 'returns 400 and writes nothing when a vital value is out of the column range' do
        payload = {
          event_type: 'pageview',
          page_url: 'https://example.com/home',
          recaptcha_token: 'valid_token',
          properties: { lcp_ms: 9_999_999_999 } # beyond 32-bit integer column
        }.to_json

        expect do
          post '/api/v1/events/collect', params: payload, headers: auth_headers(payload)
        end.to change(Event, :count).by(0)
                                    .and change(WebVital, :count).by(0)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to include('out of the accepted range')
      end

      it 'returns 400 when cls_score exceeds the decimal(6,4) column limit' do
        payload = {
          event_type: 'pageview',
          page_url: 'https://example.com/home',
          recaptcha_token: 'valid_token',
          properties: { cls_score: 123.45 } # > 99.9999 max for decimal(6,4)
        }.to_json

        post '/api/v1/events/collect', params: payload, headers: auth_headers(payload)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to include('out of the accepted range')
      end

      it 'associates subsequent requests within 30 minutes to the same session' do
        post '/api/v1/events/collect', params: valid_payload, headers: auth_headers(valid_payload)
        session_id1 = Event.last.session_id

        # Second request from same visitor (fingerprint based on IP + UA)
        post '/api/v1/events/collect', params: valid_payload, headers: auth_headers(valid_payload)
        session_id2 = Event.last.session_id

        expect(session_id1).to eq(session_id2)
        expect(Session.count).to eq(1)
      end

      it 'automatically verifies the site if it was unverified' do
        expect(site.verified).to be false
        post '/api/v1/events/collect', params: valid_payload, headers: auth_headers(valid_payload)
        expect(response).to have_http_status(:ok)
        expect(site.reload.verified).to be true
      end
    end

    context 'when validation fails' do
      it 'returns 400 bad request for invalid event_type' do
        invalid_payload = { event_type: 'invalid_type', recaptcha_token: 'valid' }.to_json
        post '/api/v1/events/collect', params: invalid_payload, headers: auth_headers(invalid_payload)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to include('Invalid event_type')
      end

      it 'returns 400 bad request if properties has more than 50 keys' do
        oversized_props = (1..51).index_by { |i| "key_#{i}" }
        invalid_payload = { event_type: 'pageview', properties: oversized_props, recaptcha_token: 'valid' }.to_json
        post '/api/v1/events/collect', params: invalid_payload, headers: auth_headers(invalid_payload)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to include('properties exceeds the limit')
      end

      it 'returns 400 bad request if x_ratio is out of bounds' do
        invalid_payload = { event_type: 'click', x_ratio: 1.2, recaptcha_token: 'valid' }.to_json
        post '/api/v1/events/collect', params: invalid_payload, headers: auth_headers(invalid_payload)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to include('x_ratio must be a number between')
      end

      it 'returns 400 bad request for a valid JSON array payload instead of 500' do
        invalid_payload = [1, 2, 3].to_json
        post '/api/v1/events/collect', params: invalid_payload, headers: auth_headers(invalid_payload)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to eq('Payload must be a JSON object')
      end

      it 'returns 400 bad request for a valid JSON null payload instead of 500' do
        invalid_payload = 'null'
        post '/api/v1/events/collect', params: invalid_payload, headers: auth_headers(invalid_payload)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to eq('Payload must be a JSON object')
      end

      it 'returns 400 bad request when x_ratio is a boolean instead of storing it as 0.0' do
        invalid_payload = { event_type: 'click', x_ratio: false, recaptcha_token: 'valid' }.to_json
        post '/api/v1/events/collect', params: invalid_payload, headers: auth_headers(invalid_payload)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to include('x_ratio must be a number between')
      end

      it 'returns 200 ok instead of 500 when page_url has a malformed percent-encoded UTM value' do
        invalid_payload = {
          event_type: 'pageview',
          page_url: 'https://example.com/?utm_source=%E0%A4%A',
          recaptcha_token: 'valid'
        }.to_json
        post '/api/v1/events/collect', params: invalid_payload, headers: auth_headers(invalid_payload)

        expect(response).to have_http_status(:ok)
        expect(Session.last.utm_source).to be_nil
      end

      it 'returns 400 bad request when user_agent is a JSON object instead of 500' do
        invalid_payload = { event_type: 'pageview', user_agent: { 'a' => 1 }, recaptcha_token: 'valid' }.to_json
        post '/api/v1/events/collect', params: invalid_payload, headers: auth_headers(invalid_payload)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to include('user_agent must be a string')
      end

      it 'returns 400 bad request when fingerprint is a JSON object instead of 500' do
        invalid_payload = { event_type: 'pageview', fingerprint: { 'a' => 1 }, recaptcha_token: 'valid' }.to_json
        post '/api/v1/events/collect', params: invalid_payload, headers: auth_headers(invalid_payload)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to include('fingerprint must be a string')
      end

      it 'returns 400 bad request when properties.fingerprint is a JSON object instead of 500' do
        invalid_payload = {
          event_type: 'pageview',
          properties: { fingerprint: { 'a' => 1 } },
          recaptcha_token: 'valid'
        }.to_json
        post '/api/v1/events/collect', params: invalid_payload, headers: auth_headers(invalid_payload)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to include('properties.fingerprint must be a string')
      end

      it 'returns 400 bad request when properties.fingerprint is JSON false instead of silently falling back' do
        invalid_payload = {
          event_type: 'pageview',
          properties: { fingerprint: false },
          recaptcha_token: 'valid'
        }.to_json
        post '/api/v1/events/collect', params: invalid_payload, headers: auth_headers(invalid_payload)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to include('properties.fingerprint must be a string')
      end
    end

    context 'when the client supplies an oversized fingerprint' do
      it 'creates the session instead of raising, storing a fixed-length hash' do
        oversized_payload = {
          event_type: 'pageview',
          fingerprint: 'a' * 10_000,
          recaptcha_token: 'valid'
        }.to_json

        expect do
          post '/api/v1/events/collect', params: oversized_payload, headers: auth_headers(oversized_payload)
        end.not_to raise_error

        expect(response).to have_http_status(:ok)
        session = Session.find(Event.find(response.parsed_body['id']).session_id)
        expect(session.fingerprint.length).to eq(64) # SHA256 hex digest, independent of input size
      end
    end

    context 'when reCAPTCHA verification fails' do
      before do
        allow(RecaptchaValidator).to receive(:verify).and_return(false)
      end

      it 'returns 400 bad request' do
        post '/api/v1/events/collect', params: valid_payload, headers: auth_headers(valid_payload)

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to include('reCAPTCHA verification failed')
      end
    end

    context 'occurred_at handling' do
      include ActiveSupport::Testing::TimeHelpers

      it 'defaults to the current time when occurred_at is blank' do
        payload = { event_type: 'pageview', occurred_at: '', recaptcha_token: 'valid' }.to_json

        freeze_time do
          post '/api/v1/events/collect', params: payload, headers: auth_headers(payload)

          expect(response).to have_http_status(:ok)
          event = Event.find(response.parsed_body['id'])
          expect(event.occurred_at).to be_within(1.second).of(Time.current)
        end
      end

      it 'defaults to the current time when occurred_at is not a parsable timestamp' do
        payload = { event_type: 'pageview', occurred_at: 'not-a-timestamp', recaptcha_token: 'valid' }.to_json

        freeze_time do
          post '/api/v1/events/collect', params: payload, headers: auth_headers(payload)

          expect(response).to have_http_status(:ok)
          event = Event.find(response.parsed_body['id'])
          expect(event.occurred_at).to be_within(1.second).of(Time.current)
        end
      end

      it 'uses the client-supplied occurred_at when it is a parsable timestamp' do
        client_time = 2.hours.ago.change(usec: 0)
        payload = { event_type: 'pageview', occurred_at: client_time.iso8601, recaptcha_token: 'valid' }.to_json

        post '/api/v1/events/collect', params: payload, headers: auth_headers(payload)

        expect(response).to have_http_status(:ok)
        event = Event.find(response.parsed_body['id'])
        expect(event.occurred_at).to eq(client_time)
      end
    end

    context 'when the client is a bot' do
      it 'detects bot from User-Agent and sets is_bot to true' do
        bot_payload = {
          event_type: 'pageview',
          user_agent: 'Googlebot/2.1 (+http://www.google.com/bot.html)',
          recaptcha_token: 'valid'
        }.to_json

        post '/api/v1/events/collect', params: bot_payload, headers: auth_headers(bot_payload)

        expect(response).to have_http_status(:ok)
        expect(Event.last.is_bot).to be(true)
        expect(Session.last.is_bot).to be(true)
      end

      it 'detects bot from special IP and sets is_bot to true' do
        # REMOTE_ADDR is recognized as the client IP by Rails
        headers = auth_headers(valid_payload).merge('REMOTE_ADDR' => '127.0.0.99')
        post '/api/v1/events/collect', params: valid_payload, headers: headers

        expect(response).to have_http_status(:ok)
        expect(Event.last.is_bot).to be(true)
        expect(Session.last.is_bot).to be(true)
      end

      it 'detects bot from behavioral click coord 0,0' do
        coord_bot_payload = {
          event_type: 'click',
          x_ratio: 0.0,
          y_ratio: 0.0,
          recaptcha_token: 'valid'
        }.to_json

        post '/api/v1/events/collect', params: coord_bot_payload, headers: auth_headers(coord_bot_payload)

        expect(response).to have_http_status(:ok)
        expect(Event.last.is_bot).to be(true)
        expect(Session.last.is_bot).to be(true)
      end
    end

    context 'when body size exceeds 32KB' do
      it 'returns 413 Payload Too Large' do
        oversized_payload = {
          event_type: 'pageview',
          padding: 'a' * 33_000,
          recaptcha_token: 'valid'
        }.to_json

        post '/api/v1/events/collect', params: oversized_payload, headers: auth_headers(oversized_payload)

        expect(response).to have_http_status(413)
        expect(response.parsed_body['error']).to eq('Payload Too Large')
      end
    end

    context 'when rate limit is exceeded' do
      include ActiveSupport::Testing::TimeHelpers

      before do
        Rack::Attack.enabled = true
        Rack::Attack.cache.store.clear
      end

      after do
        Rack::Attack.enabled = false
      end

      it 'returns 429 Too Many Requests after 100 requests in a second' do
        headers = auth_headers(valid_payload)

        freeze_time do
          # Send 100 requests
          100.times do
            post '/api/v1/events/collect', params: valid_payload, headers: headers
            expect(response).to have_http_status(:ok)
          end

          # The 101st request should be throttled
          post '/api/v1/events/collect', params: valid_payload, headers: headers
          expect(response).to have_http_status(:too_many_requests)
          expect(response.parsed_body['error']).to eq('Too Many Requests')
        end
      end

      it 'still throttles requests missing X-Site-Id instead of letting them retry forever' do
        headers = auth_headers(valid_payload).except('X-Site-Id')

        freeze_time do
          100.times do
            post '/api/v1/events/collect', params: valid_payload, headers: headers
            expect(response).to have_http_status(:unauthorized)
          end

          # The 101st request should be throttled instead of 401ing again
          post '/api/v1/events/collect', params: valid_payload, headers: headers
          expect(response).to have_http_status(:too_many_requests)
          expect(response.parsed_body['error']).to eq('Too Many Requests')
        end
      end

      it 'still throttles an unknown X-Site-Id even when the body fingerprint changes every request' do
        headers = auth_headers(valid_payload).merge('X-Site-Id' => SecureRandom.uuid)

        freeze_time do
          100.times do |i|
            payload = { event_type: 'pageview', fingerprint: "attacker-#{i}", recaptcha_token: 'valid' }.to_json
            post '/api/v1/events/collect', params: payload, headers: headers
            expect(response).to have_http_status(:unauthorized)
          end

          # The 101st request should be throttled instead of getting a fresh bucket
          payload = { event_type: 'pageview', fingerprint: 'attacker-final', recaptcha_token: 'valid' }.to_json
          post '/api/v1/events/collect', params: payload, headers: headers
          expect(response).to have_http_status(:too_many_requests)
          expect(response.parsed_body['error']).to eq('Too Many Requests')
        end
      end

      it 'still throttles a real X-Site-Id with a bad signature even when the fingerprint changes every request' do
        headers = auth_headers(valid_payload).merge('X-Api-Key' => 'not-the-real-signature')

        freeze_time do
          100.times do |i|
            payload = { event_type: 'pageview', fingerprint: "attacker-#{i}", recaptcha_token: 'valid' }.to_json
            post '/api/v1/events/collect', params: payload, headers: headers
            expect(response).to have_http_status(:unauthorized)
          end

          # The 101st request should be throttled instead of getting a fresh bucket
          payload = { event_type: 'pageview', fingerprint: 'attacker-final', recaptcha_token: 'valid' }.to_json
          post '/api/v1/events/collect', params: payload, headers: headers
          expect(response).to have_http_status(:too_many_requests)
          expect(response.parsed_body['error']).to eq('Too Many Requests')
        end
      end

      it 'still throttles a validly-signed but stale-timestamp request when the fingerprint changes every request' do
        stale_timestamp = 10.minutes.ago.to_i

        freeze_time do
          100.times do |i|
            payload = { event_type: 'pageview', fingerprint: "attacker-#{i}", recaptcha_token: 'valid' }.to_json
            headers = {
              'X-Site-Id' => site.id,
              'X-Api-Key' => sign(site.api_key, stale_timestamp, payload),
              'X-Timestamp' => stale_timestamp.to_s,
              'Content-Type' => 'application/json'
            }
            post '/api/v1/events/collect', params: payload, headers: headers
            expect(response).to have_http_status(:unauthorized)
          end

          # The 101st request should be throttled instead of getting a fresh bucket
          payload = { event_type: 'pageview', fingerprint: 'attacker-final', recaptcha_token: 'valid' }.to_json
          headers = {
            'X-Site-Id' => site.id,
            'X-Api-Key' => sign(site.api_key, stale_timestamp, payload),
            'X-Timestamp' => stale_timestamp.to_s,
            'Content-Type' => 'application/json'
          }
          post '/api/v1/events/collect', params: payload, headers: headers
          expect(response).to have_http_status(:too_many_requests)
          expect(response.parsed_body['error']).to eq('Too Many Requests')
        end
      end

      it 'does not let visitors with a blank fingerprint share a single throttle bucket' do
        blank_fp_payload = { event_type: 'pageview', fingerprint: '', recaptcha_token: 'valid' }.to_json
        headers_visitor_a = auth_headers(blank_fp_payload)
        headers_visitor_b = auth_headers(blank_fp_payload).merge('REMOTE_ADDR' => '203.0.113.5')

        freeze_time do
          60.times do
            post '/api/v1/events/collect', params: blank_fp_payload, headers: headers_visitor_a
            expect(response).to have_http_status(:ok)
          end

          60.times do
            post '/api/v1/events/collect', params: blank_fp_payload, headers: headers_visitor_b
            expect(response).to have_http_status(:ok)
          end
        end
      end

      it 'skips fingerprint JSON parsing for an invalid-credential request' do
        bogus_headers = auth_headers(valid_payload).merge('X-Api-Key' => 'not-the-real-signature')

        expect(Rack::Attack).not_to receive(:extract_fingerprint)
        post '/api/v1/events/collect', params: valid_payload, headers: bogus_headers

        expect(response).to have_http_status(:unauthorized)
      end

      it 'still parses the fingerprint for an authenticated request' do
        expect(Rack::Attack).to receive(:extract_fingerprint).and_call_original

        post '/api/v1/events/collect', params: valid_payload, headers: auth_headers(valid_payload)

        expect(response).to have_http_status(:ok)
      end

      it 'still throttles a single IP sending validly-signed requests with a different fingerprint every time' do
        freeze_time do
          100.times do |i|
            payload = { event_type: 'pageview', fingerprint: "visitor-#{i}", recaptcha_token: 'valid' }.to_json
            post '/api/v1/events/collect', params: payload, headers: auth_headers(payload)
            expect(response).to have_http_status(:ok)
          end

          # The 101st request should be throttled by IP even though every
          # request so far had a fresh, validly-signed site_id:fingerprint.
          payload = { event_type: 'pageview', fingerprint: 'visitor-final', recaptcha_token: 'valid' }.to_json
          post '/api/v1/events/collect', params: payload, headers: auth_headers(payload)
          expect(response).to have_http_status(:too_many_requests)
          expect(response.parsed_body['error']).to eq('Too Many Requests')
        end
      end

      it 'short-circuits on the cheap IP throttle without reading the body once the IP is over limit' do
        freeze_time do
          100.times do |i|
            payload = { event_type: 'pageview', fingerprint: "visitor-#{i}", recaptcha_token: 'valid' }.to_json
            post '/api/v1/events/collect', params: payload, headers: auth_headers(payload)
          end

          expect(Rack::Attack).not_to receive(:authenticated_site)

          payload = { event_type: 'pageview', fingerprint: 'visitor-final', recaptcha_token: 'valid' }.to_json
          post '/api/v1/events/collect', params: payload, headers: auth_headers(payload)
          expect(response).to have_http_status(:too_many_requests)
        end
      end
    end
  end
end
