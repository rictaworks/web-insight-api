require 'rails_helper'

RSpec.describe SessionManager do
  let(:user) { User.create!(google_sub: 'sub_session_manager', display_name: 'Session Manager Test User') }
  let(:site) { Site.create!(name: 'Test Site', url: 'https://example.com', user: user) }

  describe '.find_or_create_session' do
    it 'creates a session with the parsed UTM params from a well-formed page_url' do
      session = described_class.find_or_create_session(
        site_id: site.id,
        fingerprint: 'fp-1',
        referrer: nil,
        page_url: 'https://example.com/?utm_source=newsletter&utm_medium=email',
        is_bot: false
      )

      expect(session.utm_source).to eq('newsletter')
      expect(session.channel).to eq('email')
    end

    it 'does not raise when page_url has a malformed percent-encoded UTM value' do
      expect do
        session = described_class.find_or_create_session(
          site_id: site.id,
          fingerprint: 'fp-2',
          referrer: nil,
          page_url: 'https://example.com/?utm_source=%E0%A4%A',
          is_bot: false
        )

        expect(session.utm_source).to be_nil
      end.not_to raise_error
    end

    it 'falls back to the page_url UTM params when the payload sends blank values' do
      session = described_class.find_or_create_session(
        site_id: site.id,
        fingerprint: 'fp-3',
        referrer: nil,
        page_url: 'https://example.com/?utm_source=newsletter&utm_medium=email',
        is_bot: false,
        payload: { 'utm_source' => '', 'utm_medium' => '' }
      )

      expect(session.utm_source).to eq('newsletter')
      expect(session.channel).to eq('email')
    end

    it 'attributes utm_medium=display to the display channel even with no referrer' do
      session = described_class.find_or_create_session(
        site_id: site.id,
        fingerprint: 'fp-display-1',
        referrer: nil,
        page_url: 'https://example.com/?utm_source=news_network&utm_medium=display',
        is_bot: false
      )

      expect(session.channel).to eq('display')
    end

    it 'attributes utm_medium=display to the display channel over a non-search/social referrer' do
      session = described_class.find_or_create_session(
        site_id: site.id,
        fingerprint: 'fp-display-2',
        referrer: 'https://news.example.com/article',
        page_url: 'https://example.com/?utm_source=news_network&utm_medium=display',
        is_bot: false
      )

      expect(session.channel).to eq('display')
    end

    it 'does not raise and reuses the session when a matching row has a nil started_at' do
      existing = Session.create!(
        site_id: site.id,
        fingerprint: 'fp-4',
        is_bot: false,
        started_at: nil,
        last_seen_at: 1.minute.ago
      )

      session = nil
      expect do
        session = described_class.find_or_create_session(
          site_id: site.id,
          fingerprint: 'fp-4',
          referrer: nil,
          page_url: nil,
          is_bot: false
        )
      end.not_to raise_error

      expect(session.id).to eq(existing.id)
    end
  end
end
