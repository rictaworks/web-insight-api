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
