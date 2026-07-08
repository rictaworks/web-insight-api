require 'rails_helper'

RSpec.describe Site, type: :model do
  let(:user) { User.create!(google_sub: 'sub_test', display_name: 'Test') }

  describe 'callbacks' do
    it 'automatically generates a 64-character api_key on creation if not present' do
      site = Site.new(name: 'Test Site', url: 'https://example.com', user: user)
      expect(site.api_key).to be_nil
      expect(site.valid?).to be true
      expect(site.api_key).to be_present
      expect(site.api_key.length).to eq(64)
    end

    it 'does not overwrite an explicitly provided api_key' do
      explicit_key = 'a' * 64
      site = Site.new(name: 'Test Site', url: 'https://example.com', user: user, api_key: explicit_key)
      expect(site.valid?).to be true
      expect(site.api_key).to eq(explicit_key)
    end

    it 'automatically generates a 64-character verify_token on creation if not present' do
      site = Site.new(name: 'Test Site', url: 'https://example.com', user: user)
      expect(site.verify_token).to be_nil
      expect(site.valid?).to be true
      expect(site.verify_token).to be_present
      expect(site.verify_token.length).to eq(64)
    end

    it 'backfills verify_token on save for a legacy row whose token is blank' do
      # Simulate a row created before verify_token was required: update_column
      # bypasses validations/callbacks and writes NULL directly to the DB.
      site = Site.create!(name: 'Legacy Site', url: 'https://example.com', user: user)
      site.update_column(:verify_token, nil) # rubocop:disable Rails/SkipsModelValidations

      expect { site.update!(verified: true) }.not_to raise_error
      expect(site.reload.verify_token).to be_present
      expect(site.verify_token.length).to eq(64)
    end

    it 'backfills verify_token on save for a legacy row whose token is an empty string' do
      # Imported rows may carry '' rather than NULL; the presence validation
      # still treats it as blank, so the callback must regenerate it.
      site = Site.create!(name: 'Legacy Site', url: 'https://example.com', user: user)
      site.update_column(:verify_token, '') # rubocop:disable Rails/SkipsModelValidations

      expect { site.update!(verified: true) }.not_to raise_error
      expect(site.reload.verify_token).to be_present
      expect(site.verify_token.length).to eq(64)
    end
  end

  describe '#generate_snippet' do
    it 'returns a valid javascript code string including site id and api key' do
      site = Site.create!(name: 'Test Site', url: 'https://example.com', user: user)
      snippet = site.generate_snippet
      expect(snippet).to be_a(String)
      expect(snippet).to include(site.id)
      expect(snippet).to include(site.api_key)
      expect(snippet).to include('fetch')
    end

    it 'persists and sends a stable per-browser fingerprint' do
      site = Site.create!(name: 'Test Site', url: 'https://example.com', user: user)
      snippet = site.generate_snippet

      # localStorage-backed id keeps sessionization off the IP+UA fallback that
      # merges distinct visitors behind a shared IP.
      expect(snippet).to include('localStorage')
      expect(snippet).to include('getClientFingerprint')
      expect(snippet).to include('fingerprint: getClientFingerprint()')
    end

    it 'acquires and sends a reCAPTCHA token when a site key is configured' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('RECAPTCHA_SITE_KEY').and_return('site_key_123')

      site = Site.create!(name: 'Test Site', url: 'https://example.com', user: user)
      snippet = site.generate_snippet

      expect(snippet).to include('recaptcha_token')
      expect(snippet).to include('grecaptcha')
      expect(snippet).to include('site_key_123')
    end

    it 'collects and reports Core Web Vitals so the default install populates performance data' do
      site = Site.create!(name: 'Test Site', url: 'https://example.com', user: user)
      snippet = site.generate_snippet

      # The default install must actually observe the vitals, otherwise WebVital
      # rows are never created and GET /performance stays empty.
      expect(snippet).to include('PerformanceObserver')
      expect(snippet).to include('largest-contentful-paint')
      expect(snippet).to include('first-input')
      expect(snippet).to include('layout-shift')

      # And it must ship them to the collector as the vital property keys the
      # backend recognises, on a custom event.
      expect(snippet).to include('lcp_ms')
      expect(snippet).to include('fid_ms')
      expect(snippet).to include('cls_score')
      expect(snippet).to include('ttfb_ms')
      expect(snippet).to include('fcp_ms')
      expect(snippet).to include("trackEvent('custom'")
    end

    it 'sends the vitals report on an unload-safe keepalive path' do
      site = Site.create!(name: 'Test Site', url: 'https://example.com', user: user)
      snippet = site.generate_snippet

      # The single vitals report fires from the hidden/pagehide path; the fetch
      # must be marked keepalive so the browser does not cancel it during unload.
      expect(snippet).to include('keepalive')
    end

    it 'processes pending observer records before disconnecting on flush' do
      site = Site.create!(name: 'Test Site', url: 'https://example.com', user: user)
      snippet = site.generate_snippet

      # takeRecords() drains entries queued right before hide; they must be run
      # through the metric callback, not discarded.
      expect(snippet).to include('takeRecords')
      expect(snippet).to match(/\.forEach\(\s*\w+\.callback\s*\)/)
    end

    it 'tags the internal vitals ping so traffic aggregation can exclude it' do
      site = Site.create!(name: 'Test Site', url: 'https://example.com', user: user)
      snippet = site.generate_snippet

      # The vitals payload is sent as a custom event; it must carry the marker
      # property AnalyticsEngine filters on, so its unload-time session is never
      # counted as a zero-pageview traffic session.
      expect(snippet).to include("#{EventCollector::INTERNAL_VITALS_PROPERTY}\": true")
    end

    it 're-signs the drained vitals synchronously so no await precedes the unload fetch' do
      site = Site.create!(name: 'Test Site', url: 'https://example.com', user: user)
      snippet = site.generate_snippet

      # When takeRecords() yields final metrics at hide, the request is re-signed
      # with a synchronous HMAC (not the async WebCrypto path) so the freshest
      # vitals are sent and the keepalive fetch is fired with zero awaits — a
      # browser will not keep an unloading page alive for a promise callback.
      expect(snippet).to include('buildSignedRequestSync')
      expect(snippet).to include('hmacSha256Hex')
      expect(snippet).to match(/drainedNewRecords/)
    end

    it 'computes CLS using the session-window maximum, not the lifetime sum' do
      site = Site.create!(name: 'Test Site', url: 'https://example.com', user: user)
      snippet = site.generate_snippet

      # Core Web Vitals defines CLS as the max session-window sum (1s gap / 5s
      # cap), so the snippet must track session state rather than a running total.
      expect(snippet).to include('sessionValue')
      expect(snippet).to include('1000') # 1s gap between shifts
      expect(snippet).to include('5000') # 5s session cap
    end

    it 'reports CLS as null when the layout-shift entry type is unsupported' do
      site = Site.create!(name: 'Test Site', url: 'https://example.com', user: user)
      snippet = site.generate_snippet

      # Starts as null (not measured) and only becomes a numeric 0 when the
      # layout-shift observer registers, so unsupported browsers do not report a
      # misleadingly "good" CLS of 0.
      expect(snippet).to include('cls_score: null')
      expect(snippet).to include('clsSupported')
      expect(snippet).to match(/if\s*\(\s*clsSupported\s*\)\s*\{\s*vitals\.cls_score\s*=\s*0/)
    end

    it 'sends the vitals report from a pre-signed request without awaiting reCAPTCHA at unload' do
      site = Site.create!(name: 'Test Site', url: 'https://example.com', user: user)
      snippet = site.generate_snippet

      # The signed request is prepared ahead of time and fired synchronously in
      # flush, so no reCAPTCHA/crypto await sits before the keepalive fetch on
      # the unload path where it could be abandoned.
      expect(snippet).to include('prepareVitalsRequest')
      expect(snippet).to include('buildSignedRequest')
      expect(snippet).to include('sendSignedRequest(preparedRequest')
      # The reCAPTCHA token is pre-acquired (not awaited at flush) and refreshed
      # on an interval so it cannot expire before use.
      expect(snippet).to include('refreshVitalsToken')
      expect(snippet).to include('recaptchaToken: vitalsToken')
      expect(snippet).to match(/setInterval\(/)
    end

    it 'still sends a recaptcha_token field even when no site key is configured' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('RECAPTCHA_SITE_KEY').and_return(nil)

      site = Site.create!(name: 'Test Site', url: 'https://example.com', user: user)
      snippet = site.generate_snippet

      expect(snippet).to include('recaptcha_token')
      # No key configured → the injected key is null, so the loader is a no-op.
      expect(snippet).to include('recaptchaSiteKey = null')
    end
  end
end
