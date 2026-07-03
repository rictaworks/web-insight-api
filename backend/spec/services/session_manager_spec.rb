require 'rails_helper'

RSpec.describe SessionManager do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(google_sub: 'sub_session_manager', display_name: 'Session Manager Test User') }
  let(:site) { Site.create!(name: 'Test Site', url: 'https://example.com', user: user) }

  def collect(fingerprint:, referrer: nil, page_url: nil, is_bot: false, payload: {})
    described_class.find_or_create_session(
      site_id: site.id,
      fingerprint: fingerprint,
      referrer: referrer,
      page_url: page_url,
      is_bot: is_bot,
      payload: payload
    )
  end

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

  # Acceptance criteria (#7): NEW → ACTIVE → IDLE(30min) → EXPIRED,
  # last_seen_at refresh, and a JST day change forcing a fresh session.
  describe 'session state transitions' do
    it 'creates a brand-new session for the first request of a fingerprint (NEW)' do
      expect { collect(fingerprint: 'fp-new') }.to change(Session, :count).by(1)
    end

    it 'reuses the same session and refreshes last_seen_at within 30 minutes (ACTIVE)' do
      jst = ActiveSupport::TimeZone['Asia/Tokyo']

      # Freeze the initial request to a fixed mid-day JST timestamp so that
      # advancing 20 minutes never crosses the JST day boundary (which would
      # otherwise force a fresh session and fail this reuse assertion).
      first = nil
      original_last_seen = nil
      travel_to(jst.parse('2026-07-03 12:00:00')) do
        first = collect(fingerprint: 'fp-active')
        original_last_seen = first.last_seen_at
      end

      second = nil
      travel_to(jst.parse('2026-07-03 12:20:00')) do
        second = collect(fingerprint: 'fp-active')
      end

      expect(second.id).to eq(first.id)
      expect(second.last_seen_at).to be > original_last_seen
      expect(Session.where(fingerprint: 'fp-active').count).to eq(1)
    end

    it 'starts a new session once activity has been idle for more than 30 minutes (EXPIRED → NEW)' do
      jst = ActiveSupport::TimeZone['Asia/Tokyo']

      # Freeze to a fixed mid-day JST timestamp so the new session is forced by
      # the 31-minute idle window, not by an incidental JST day change.
      first = nil
      travel_to(jst.parse('2026-07-03 12:00:00')) do
        first = collect(fingerprint: 'fp-expired')
      end

      second = nil
      travel_to(jst.parse('2026-07-03 12:31:00')) do
        second = collect(fingerprint: 'fp-expired')
      end

      expect(second.id).not_to eq(first.id)
      expect(Session.where(fingerprint: 'fp-expired').count).to eq(2)
    end

    it 'starts a new session when the JST calendar day changes even within 30 minutes' do
      jst = ActiveSupport::TimeZone['Asia/Tokyo']

      travel_to(jst.parse('2026-07-03 00:10:00')) do
        # Previous activity was 15 minutes ago (within tolerance) but on the
        # previous JST day, so the day change must force a fresh session.
        yesterday = Session.create!(
          site_id: site.id,
          fingerprint: 'fp-midnight',
          is_bot: false,
          started_at: jst.parse('2026-07-02 23:55:00'),
          last_seen_at: jst.parse('2026-07-02 23:55:00')
        )

        session = collect(fingerprint: 'fp-midnight')

        expect(session.id).not_to eq(yesterday.id)
        expect(Session.where(fingerprint: 'fp-midnight').count).to eq(2)
      end
    end

    it 'keeps sessions separate per fingerprint on the same site' do
      a = collect(fingerprint: 'fp-visitor-a')
      b = collect(fingerprint: 'fp-visitor-b')

      expect(a.id).not_to eq(b.id)
    end

    it 'propagates the bot flag onto an existing human session on a later bot request' do
      jst = ActiveSupport::TimeZone['Asia/Tokyo']

      # Freeze both requests to one fixed JST day so the second call reuses the
      # existing session; without this, a run straddling JST midnight would
      # start a fresh session and break the reuse (count == 1) assertion.
      session = nil
      travel_to(jst.parse('2026-07-03 12:00:00')) do
        collect(fingerprint: 'fp-turns-bot', is_bot: false)
        session = collect(fingerprint: 'fp-turns-bot', is_bot: true)
      end

      expect(session.is_bot).to be(true)
      expect(Session.where(fingerprint: 'fp-turns-bot').count).to eq(1)
    end
  end

  # Acceptance criteria (#7): channel auto-detection across all reachable
  # buckets (organic / paid / referral / social / email / direct / display).
  describe 'channel classification' do
    it 'classifies a paid campaign (utm_medium=cpc) as paid' do
      session = collect(
        fingerprint: 'fp-paid',
        page_url: 'https://example.com/?utm_source=google&utm_medium=cpc'
      )
      expect(session.channel).to eq('paid')
    end

    it 'classifies a search-engine referrer as organic' do
      session = collect(fingerprint: 'fp-organic', referrer: 'https://www.google.com/search?q=foo')
      expect(session.channel).to eq('organic')
    end

    it 'classifies a social referrer as social' do
      session = collect(fingerprint: 'fp-social', referrer: 'https://twitter.com/someone/status/1')
      expect(session.channel).to eq('social')
    end

    it 'classifies a generic external referrer as referral' do
      session = collect(fingerprint: 'fp-referral', referrer: 'https://some-blog.example/post')
      expect(session.channel).to eq('referral')
    end

    it 'classifies a request with no referrer and no UTM as direct' do
      session = collect(fingerprint: 'fp-direct', referrer: nil, page_url: 'https://example.com/')
      expect(session.channel).to eq('direct')
    end
  end
end
