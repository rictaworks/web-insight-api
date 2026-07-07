require 'rails_helper'

RSpec.describe AnalyticsEngine, type: :service do
  let(:user) { User.create!(google_sub: 'user_123', display_name: 'Alice') }
  let(:site) { Site.create!(name: 'My Site', url: 'https://mysite.com', user: user) }

  before do
    Rails.cache.clear
  end

  describe '.pageviews' do
    it 'caches the result for 5 minutes' do
      expect(Rails.cache).to receive(:fetch).with("pageviews_#{site.id}_7d_day",
                                                  expires_in: 5.minutes).and_call_original
      AnalyticsEngine.pageviews(site, period: '7d', axis: 'day')
    end

    context 'with events' do
      let!(:session1) { Session.create!(site: site, fingerprint: 'fp1', started_at: 1.day.ago) }
      let!(:session2) { Session.create!(site: site, fingerprint: 'fp2', started_at: 2.days.ago) }
      let!(:bot_session) { Session.create!(site: site, fingerprint: 'fp3', is_bot: true, started_at: 1.day.ago) }

      before do
        # Current period events
        Event.create!(site: site, session: session1, event_type: 'pageview', occurred_at: 1.day.ago, is_bot: false)
        Event.create!(site: site, session: session1, event_type: 'click', occurred_at: 1.day.ago, is_bot: false)
        Event.create!(site: site, session: session2, event_type: 'pageview', occurred_at: 2.days.ago, is_bot: false)
        # Bot events (should be excluded)
        Event.create!(site: site, session: bot_session, event_type: 'pageview', occurred_at: 1.day.ago, is_bot: true)

        # Previous period events
        # With period = 7d, current period starts 6 days ago. Previous period starts 13 days ago and ends 6 days ago.
        # 9 days ago is in the previous period range.
        prev_session1 = Session.create!(site: site, fingerprint: 'fp_prev1', started_at: 9.days.ago)
        Event.create!(site: site, session: prev_session1, event_type: 'pageview', occurred_at: 9.days.ago,
                      is_bot: false)
      end

      it 'excludes events whose session was later marked as a bot' do
        # A session can be classified as a bot after its first event was already
        # stored with events.is_bot=false. Those early events must still be excluded.
        late_bot_session = Session.create!(site: site, fingerprint: 'fp_late_bot', is_bot: true, started_at: 1.day.ago)
        Event.create!(site: site, session: late_bot_session, event_type: 'pageview', occurred_at: 1.day.ago,
                      is_bot: false)

        result = AnalyticsEngine.pageviews(site, period: '7d', axis: 'day')

        expect(result[:totals][:pv]).to eq(2) # unchanged: the late-bot pageview is excluded
        expect(result[:totals][:uv]).to eq(2) # fp_late_bot must not be counted
        expect(result[:totals][:session]).to eq(2) # late_bot_session must not be counted
      end

      it 'aggregates pageviews correctly' do
        result = AnalyticsEngine.pageviews(site, period: '7d', axis: 'day')

        expect(result[:totals][:pv]).to eq(2) # 2 normal pageviews in current period (1 day ago, 2 days ago)
        expect(result[:totals][:uv]).to eq(2) # fp1 and fp2
        expect(result[:totals][:session]).to eq(2) # session1 and session2

        # Previous period had 1 pageview, 1 uv, 1 session
        expect(result[:change_rates][:pv]).to eq(100.0)
        expect(result[:change_rates][:uv]).to eq(100.0)
        expect(result[:change_rates][:session]).to eq(100.0)

        # Series should contain 7 data points
        expect(result[:series].size).to eq(7)

        # Check grouping logic
        label_1d = 1.day.ago.in_time_zone.strftime('%Y-%m-%d')
        label_2d = 2.days.ago.in_time_zone.strftime('%Y-%m-%d')

        dp_1d = result[:series].find { |dp| dp[:label] == label_1d }
        dp_2d = result[:series].find { |dp| dp[:label] == label_2d }

        expect(dp_1d[:pv]).to eq(1)
        expect(dp_1d[:uv]).to eq(1)
        expect(dp_1d[:session]).to eq(1)

        expect(dp_2d[:pv]).to eq(1)
        expect(dp_2d[:uv]).to eq(1)
        expect(dp_2d[:session]).to eq(1)
      end
    end
  end

  describe '.heatmap' do
    let(:page_url) { 'https://mysite.com/home' }

    it 'caches the result for 5 minutes' do
      expect(Rails.cache).to receive(:fetch).with("heatmap_#{site.id}_#{page_url}_desktop",
                                                  expires_in: 5.minutes).and_call_original
      AnalyticsEngine.heatmap(site, url: page_url, viewport: 'desktop')
    end

    context 'with click events' do
      let!(:desktop_session) { Session.create!(site: site, fingerprint: 'fp1', started_at: 1.day.ago) }
      let!(:mobile_session) { Session.create!(site: site, fingerprint: 'fp2', started_at: 1.day.ago) }
      let!(:bot_session) { Session.create!(site: site, fingerprint: 'fp3', is_bot: true, started_at: 1.day.ago) }

      before do
        desktop_ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
        mobile_ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X)'

        Event.create!(site: site, session: desktop_session, event_type: 'click', page_url: page_url, x_ratio: 0.1,
                      y_ratio: 0.2, user_agent: desktop_ua, occurred_at: 1.hour.ago, is_bot: false)
        Event.create!(site: site, session: desktop_session, event_type: 'click', page_url: page_url, x_ratio: 0.1,
                      y_ratio: 0.2, user_agent: desktop_ua, occurred_at: 45.minutes.ago, is_bot: false)
        Event.create!(site: site, session: desktop_session, event_type: 'click', page_url: page_url, x_ratio: 0.95,
                      y_ratio: 0.99, user_agent: desktop_ua, occurred_at: 30.minutes.ago, is_bot: false)
        Event.create!(site: site, session: desktop_session, event_type: 'click', page_url: 'https://mysite.com/other',
                      x_ratio: 0.1, y_ratio: 0.2, user_agent: desktop_ua, occurred_at: 15.minutes.ago, is_bot: false)
        Event.create!(site: site, session: mobile_session, event_type: 'click', page_url: page_url, x_ratio: 0.1,
                      y_ratio: 0.2, user_agent: mobile_ua, occurred_at: 10.minutes.ago, is_bot: false)
        Event.create!(site: site, session: bot_session, event_type: 'click', page_url: page_url, x_ratio: 0.1,
                      y_ratio: 0.2, user_agent: desktop_ua, occurred_at: 5.minutes.ago, is_bot: true)
        Event.create!(site: site, session: desktop_session, event_type: 'click', page_url: page_url, x_ratio: 0.1,
                      y_ratio: 0.2, user_agent: desktop_ua, occurred_at: 5.minutes.ago, is_bot: true)
      end

      it 'calculates desktop heatmap grid correctly' do
        result = AnalyticsEngine.heatmap(site, url: page_url, viewport: 'desktop')

        expect(result[:max_count]).to eq(2)
        expect(result[:grid].size).to eq(20)
        expect(result[:grid][0].size).to eq(20)

        expect(result[:grid][4][2]).to eq(2)
        expect(result[:grid][19][19]).to eq(1)
        expect(result[:grid][0][0]).to eq(0)
      end

      it 'calculates mobile heatmap grid correctly' do
        result = AnalyticsEngine.heatmap(site, url: page_url, viewport: 'mobile')

        expect(result[:max_count]).to eq(1)
        expect(result[:grid][4][2]).to eq(1)
        expect(result[:grid][19][19]).to eq(0)
      end
    end
  end
end
