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

      it 'excludes the internal Web Vitals ping from traffic totals and series' do
        # A page held open past the session cutoff sends its unload vitals ping
        # as a custom event, which SessionManager lands in a fresh session. That
        # zero-pageview session must not inflate session/uv totals.
        vitals_session = Session.create!(site: site, fingerprint: 'fp_vitals', started_at: 1.day.ago)
        Event.create!(
          site: site, session: vitals_session, event_type: 'custom', occurred_at: 1.day.ago, is_bot: false,
          properties: { 'lcp_ms' => 2400, EventCollector::INTERNAL_VITALS_PROPERTY => true }
        )

        result = AnalyticsEngine.pageviews(site, period: '7d', axis: 'day')

        # Unchanged from the baseline below: the vitals ping and its session are ignored.
        expect(result[:totals][:pv]).to eq(2)
        expect(result[:totals][:uv]).to eq(2) # fp_vitals must not be counted
        expect(result[:totals][:session]).to eq(2) # vitals_session must not be counted

        label_1d = 1.day.ago.in_time_zone.strftime('%Y-%m-%d')
        dp_1d = result[:series].find { |dp| dp[:label] == label_1d }
        expect(dp_1d[:session]).to eq(1) # only session1, not vitals_session
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

    context 'with query strings, fragments and trailing slashes on the same page' do
      let(:canonical_url) { 'https://mysite.com/home' }
      let!(:session) { Session.create!(site: site, fingerprint: 'fp1', started_at: 1.day.ago) }
      let(:desktop_ua) { 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' }

      before do
        # Same logical page reached via different spellings. All clicks land at
        # the same coordinate and must aggregate into a single grid cell.
        %w[
          https://mysite.com/home
          https://mysite.com/home?utm_source=ad
          https://mysite.com/home#section
          https://mysite.com/home/
        ].each_with_index do |raw_url, i|
          Event.create!(site: site, session: session, event_type: 'click', page_url: raw_url, x_ratio: 0.1,
                        y_ratio: 0.2, user_agent: desktop_ua, occurred_at: (i + 1).minutes.ago, is_bot: false)
        end
      end

      it 'aggregates clicks on the same page regardless of query/fragment/trailing slash' do
        result = AnalyticsEngine.heatmap(site, url: canonical_url, viewport: 'desktop')

        # All four spellings collapse to one page → one cell with count 4.
        expect(result[:grid][4][2]).to eq(4)
        expect(result[:max_count]).to eq(4)
      end

      it 'matches the canonical page even when called with a query string' do
        result = AnalyticsEngine.heatmap(site, url: 'https://mysite.com/home?ref=twitter', viewport: 'desktop')

        expect(result[:grid][4][2]).to eq(4)
      end

      it 'includes clicks whose raw href kept the explicit default port' do
        # A href stored as https://mysite.com:443/home normalizes to the same
        # portless key and must be counted, not filtered out by the SQL prefilter.
        Event.create!(site: site, session: session, event_type: 'click', page_url: 'https://mysite.com:443/home',
                      x_ratio: 0.1, y_ratio: 0.2, user_agent: desktop_ua, occurred_at: 30.seconds.ago, is_bot: false)

        result = AnalyticsEngine.heatmap(site, url: canonical_url, viewport: 'desktop')

        expect(result[:grid][4][2]).to eq(5) # 4 portless spellings + the :443 one
      end

      it 'does not leak clicks from a different page that shares the URL prefix' do
        # "/homepage" shares the "/home" prefix; the SQL predicate must not match
        # it, and the exact normalized comparison must exclude it either way.
        Event.create!(site: site, session: session, event_type: 'click', page_url: 'https://mysite.com/homepage',
                      x_ratio: 0.5, y_ratio: 0.5, user_agent: desktop_ua, occurred_at: 1.minute.ago, is_bot: false)

        result = AnalyticsEngine.heatmap(site, url: canonical_url, viewport: 'desktop')

        expect(result[:grid][4][2]).to eq(4) # only the /home clicks
        expect(result[:grid][10][10]).to eq(0) # the /homepage click must not appear
        expect(result[:max_count]).to eq(4)
      end
    end

    context 'for the site root' do
      let!(:session) { Session.create!(site: site, fingerprint: 'fp1', started_at: 1.day.ago) }
      let(:desktop_ua) { 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' }

      before do
        # Root spellings that all normalize to "https://mysite.com/", including
        # the origin-only href with no path slash.
        %w[
          https://mysite.com/
          https://mysite.com
          https://mysite.com/?utm_source=ad
          https://mysite.com/#top
        ].each_with_index do |raw_url, i|
          Event.create!(site: site, session: session, event_type: 'click', page_url: raw_url, x_ratio: 0.1,
                        y_ratio: 0.2, user_agent: desktop_ua, occurred_at: (i + 1).minutes.ago, is_bot: false)
        end
        # A non-root page that must NOT be counted in the root heatmap.
        Event.create!(site: site, session: session, event_type: 'click', page_url: 'https://mysite.com/about',
                      x_ratio: 0.5, y_ratio: 0.5, user_agent: desktop_ua, occurred_at: 10.minutes.ago, is_bot: false)
      end

      it 'aggregates only root clicks (including the origin-only form) and excludes other pages' do
        result = AnalyticsEngine.heatmap(site, url: 'https://mysite.com/', viewport: 'desktop')

        expect(result[:grid][4][2]).to eq(4) # all four root spellings
        expect(result[:grid][10][10]).to eq(0) # /about must not appear
        expect(result[:max_count]).to eq(4)
      end
    end
  end

  describe '.performance' do
    it 'caches the result for 5 minutes' do
      expect(Rails.cache).to receive(:fetch).with("performance_#{site.id}_7d_p75",
                                                  expires_in: 5.minutes).and_call_original
      AnalyticsEngine.performance(site, period: '7d', percentile: 'p75')
    end

    context 'with WebVitals records' do
      let!(:session) { Session.create!(site: site, fingerprint: 'fp1', started_at: 1.day.ago) }
      let!(:bot_session) { Session.create!(site: site, fingerprint: 'fp_bot', is_bot: true, started_at: 1.day.ago) }

      before do
        [1000, 2000, 3000, 4000, 5000].each_with_index do |lcp, idx|
          WebVital.create!(
            site: site,
            session: session,
            page_url: 'https://mysite.com/home',
            lcp_ms: lcp,
            fid_ms: 50 + (idx * 50),
            cls_score: 0.05 + (idx * 0.05),
            ttfb_ms: 100 + (idx * 100),
            fcp_ms: 500 + (idx * 500),
            created_at: 1.day.ago
          )
        end

        WebVital.create!(
          site: site,
          session: bot_session,
          page_url: 'https://mysite.com/home',
          lcp_ms: 100,
          created_at: 1.day.ago
        )

        WebVital.create!(
          site: site,
          session: session,
          page_url: 'https://mysite.com/home',
          lcp_ms: 9999,
          created_at: 10.days.ago
        )
      end

      it 'calculates the 75th percentile (p75) values and ratings correctly' do
        result = AnalyticsEngine.performance(site, period: '7d', percentile: 'p75')

        expect(result[:lcp][:value]).to eq(4000)
        expect(result[:lcp][:rating]).to eq('needs_improvement')

        expect(result[:fid][:value]).to eq(200)
        expect(result[:fid][:rating]).to eq('needs_improvement')

        expect(result[:cls][:value]).to eq(0.20)
        expect(result[:cls][:rating]).to eq('needs_improvement')

        expect(result[:ttfb][:value]).to eq(400)
        expect(result[:ttfb][:rating]).to eq('good')

        expect(result[:fcp][:value]).to eq(2000)
        expect(result[:fcp][:rating]).to eq('needs_improvement')
      end

      it 'calculates p50 correctly' do
        result = AnalyticsEngine.performance(site, period: '7d', percentile: 'p50')

        expect(result[:lcp][:value]).to eq(3000)
        expect(result[:lcp][:rating]).to eq('needs_improvement')
      end

      it 'calculates p95 correctly' do
        result = AnalyticsEngine.performance(site, period: '7d', percentile: 'p95')

        expect(result[:lcp][:value]).to eq(4800)
        expect(result[:lcp][:rating]).to eq('poor')
      end
    end

    context 'with no WebVitals data' do
      it 'returns nil values and ratings' do
        result = AnalyticsEngine.performance(site, period: '7d', percentile: 'p75')

        %i[lcp fid cls ttfb fcp].each do |metric|
          expect(result[metric][:value]).to be_nil
          expect(result[metric][:rating]).to be_nil
        end
      end
    end

    context 'with values exactly on the good/needs_improvement threshold' do
      let!(:session) { Session.create!(site: site, fingerprint: 'fp_boundary', started_at: 1.day.ago) }

      before do
        WebVital.create!(
          site: site,
          session: session,
          page_url: 'https://mysite.com/home',
          lcp_ms: 2500,
          fid_ms: 100,
          cls_score: 0.1,
          ttfb_ms: 800,
          fcp_ms: 1800,
          created_at: 1.day.ago
        )
      end

      it 'rates each metric at its exact threshold as good' do
        result = AnalyticsEngine.performance(site, period: '7d', percentile: 'p75')

        expect(result[:lcp][:rating]).to eq('good')
        expect(result[:fid][:rating]).to eq('good')
        expect(result[:cls][:rating]).to eq('good')
        expect(result[:ttfb][:rating]).to eq('good')
        expect(result[:fcp][:rating]).to eq('good')
      end
    end

    context 'with an interpolated percentile just over a threshold' do
      let!(:session) { Session.create!(site: site, fingerprint: 'fp_interp', started_at: 1.day.ago) }

      before do
        # p75 of these four values interpolates to 2500.25 ms:
        # sorted[2] + 0.25 * (sorted[3] - sorted[2]) = 2500 + 0.25 = 2500.25.
        [1000, 2000, 2500, 2501].each do |lcp|
          WebVital.create!(
            site: site, session: session, page_url: 'https://mysite.com/home',
            lcp_ms: lcp, created_at: 1.day.ago
          )
        end
      end

      it 'classifies from the raw percentile, not the rounded display value' do
        result = AnalyticsEngine.performance(site, period: '7d', percentile: 'p75')

        # 2500.25 rounds to 2500 for display, but exceeds the 2500 good threshold
        # so it must be rated needs_improvement, not good.
        expect(result[:lcp][:value]).to eq(2500)
        expect(result[:lcp][:rating]).to eq('needs_improvement')
      end
    end
  end

  describe '.retention' do
    include ActiveSupport::Testing::TimeHelpers

    let(:jst) { ActiveSupport::TimeZone['Asia/Tokyo'] }

    it 'caches the result for 5 minutes' do
      expect(Rails.cache).to receive(:fetch).with("retention_#{site.id}_week",
                                                  expires_in: 5.minutes).and_call_original
      AnalyticsEngine.retention(site, cohort_unit: 'week')
    end

    context 'with sessions' do
      it 'excludes bot sessions' do
        travel_to(jst.parse('2026-07-09 12:00:00')) do
          # Create a bot session
          Session.create!(site: site, fingerprint: 'fp_bot', is_bot: true, started_at: 1.day.ago)

          # Create a regular session
          Session.create!(site: site, fingerprint: 'fp_regular', is_bot: false, started_at: 1.day.ago)

          result = AnalyticsEngine.retention(site, cohort_unit: 'week')

          # Check that fp_bot is not counted in the cohort size of the current week (2026-07-06)
          current_cohort = result[:matrix].find { |c| c[:cohort] == '2026-07-06' }
          expect(current_cohort[:cohort_size]).to eq(1)
        end
      end

      it 'calculates weekly retention matrix correctly' do
        travel_to(jst.parse('2026-07-09 12:00:00')) do # Thursday. Current week starts Monday 2026-07-06.
          # Cohort 2 weeks ago (2026-06-22)
          # User 1: starts 2 weeks ago, returns 1 week ago, and returns this week
          Session.create!(site: site, fingerprint: 'user1', started_at: 2.weeks.ago)
          Session.create!(site: site, fingerprint: 'user1', started_at: 1.week.ago)
          Session.create!(site: site, fingerprint: 'user1', started_at: Time.current)

          # User 2: starts 2 weeks ago, does not return
          Session.create!(site: site, fingerprint: 'user2', started_at: 2.weeks.ago)

          # Cohort 1 week ago (2026-06-29)
          # User 3: starts 1 week ago, returns this week
          Session.create!(site: site, fingerprint: 'user3', started_at: 1.week.ago)
          Session.create!(site: site, fingerprint: 'user3', started_at: Time.current)

          # Cohort this week (2026-07-06)
          # User 4: starts this week
          Session.create!(site: site, fingerprint: 'user4', started_at: Time.current)

          result = AnalyticsEngine.retention(site, cohort_unit: 'week')

          # Matrix should have 12 rows
          expect(result[:matrix].size).to eq(12)
          expect(result[:cohort_unit]).to eq('week')

          # Find specific cohorts
          c_2w = result[:matrix].find { |c| c[:cohort] == '2026-06-22' }
          c_1w = result[:matrix].find { |c| c[:cohort] == '2026-06-29' }
          c_this = result[:matrix].find { |c| c[:cohort] == '2026-07-06' }

          # Cohort 2 weeks ago size: 2 (user1, user2)
          expect(c_2w[:cohort_size]).to eq(2)
          # Period 0 (same week): 100.0%
          expect(c_2w[:activity][0]).to eq(100.0)
          # Period 1 (1 week later): user1 active -> 1 / 2 = 50.0%
          expect(c_2w[:activity][1]).to eq(50.0)
          # Period 2 (2 weeks later, which is this week): user1 active -> 1 / 2 = 50.0%
          expect(c_2w[:activity][2]).to eq(50.0)
          # Period 3 (future): nil
          expect(c_2w[:activity][3]).to be_nil

          # Cohort 1 week ago size: 1 (user3)
          expect(c_1w[:cohort_size]).to eq(1)
          expect(c_1w[:activity][0]).to eq(100.0)
          # Period 1 (1 week later): user3 active -> 1 / 1 = 100.0%
          expect(c_1w[:activity][1]).to eq(100.0)
          # Period 2 (future): nil
          expect(c_1w[:activity][2]).to be_nil

          # Cohort this week size: 1 (user4)
          expect(c_this[:cohort_size]).to eq(1)
          expect(c_this[:activity][0]).to eq(100.0)
          # Period 1 (future): nil
          expect(c_this[:activity][1]).to be_nil
        end
      end

      it 'excludes sessions whose only event is the internal Web Vitals ping' do
        travel_to(jst.parse('2026-07-09 12:00:00')) do # Current week starts 2026-07-06.
          marker = EventCollector::INTERNAL_VITALS_PROPERTY

          # User acquired last week (2026-06-29) with a real pageview.
          cohort_session = Session.create!(site: site, fingerprint: 'u_vitals', started_at: 1.week.ago)
          Event.create!(site: site, session: cohort_session, event_type: 'pageview', page_url: '/',
                        occurred_at: 1.week.ago, is_bot: false)

          # This week the same user only sent the tracking snippet's internal Web
          # Vitals ping (a fresh session with no real revisit).
          vitals_session = Session.create!(site: site, fingerprint: 'u_vitals', started_at: Time.current)
          Event.create!(site: site, session: vitals_session, event_type: 'custom', page_url: '/',
                        occurred_at: Time.current, is_bot: false, properties: { marker => true })

          result = AnalyticsEngine.retention(site, cohort_unit: 'week')
          c_1w = result[:matrix].find { |c| c[:cohort] == '2026-06-29' }

          expect(c_1w[:cohort_size]).to eq(1)
          expect(c_1w[:activity][0]).to eq(100.0) # acquisition week
          # The vitals-only session this week must NOT count as a revisit.
          expect(c_1w[:activity][1]).to eq(0.0)
        end
      end

      it 'detects vitals-only sessions across id-lookup batches' do
        stub_const('AnalyticsEngine::VITALS_LOOKUP_BATCH_SIZE', 1)
        travel_to(jst.parse('2026-07-09 12:00:00')) do
          marker = EventCollector::INTERNAL_VITALS_PROPERTY

          # Three users acquired last week (real pageview), each with a vitals-only
          # session this week. With the batch size forced to 1, the id lookup spans
          # many batches and must still flag every vitals-only session.
          %w[a b c].each do |suffix|
            cohort_session = Session.create!(site: site, fingerprint: "u_#{suffix}", started_at: 1.week.ago)
            Event.create!(site: site, session: cohort_session, event_type: 'pageview', page_url: '/',
                          occurred_at: 1.week.ago, is_bot: false)

            vitals_session = Session.create!(site: site, fingerprint: "u_#{suffix}", started_at: Time.current)
            Event.create!(site: site, session: vitals_session, event_type: 'custom', page_url: '/',
                          occurred_at: Time.current, is_bot: false, properties: { marker => true })
          end

          result = AnalyticsEngine.retention(site, cohort_unit: 'week')
          c_1w = result[:matrix].find { |c| c[:cohort] == '2026-06-29' }

          expect(c_1w[:cohort_size]).to eq(3)
          expect(c_1w[:activity][0]).to eq(100.0)
          # Every this-week session is vitals-only, so none counts as a revisit.
          expect(c_1w[:activity][1]).to eq(0.0)
        end
      end

      it 'calculates monthly retention matrix correctly' do
        travel_to(jst.parse('2026-07-09 12:00:00')) do
          # Cohort 1 month ago (2026-06-01)
          # User 1: starts 1 month ago, returns this month (2026-07-01)
          Session.create!(site: site, fingerprint: 'user1', started_at: 1.month.ago)
          Session.create!(site: site, fingerprint: 'user1', started_at: Time.current)

          # Cohort this month (2026-07-01)
          # User 2: starts this month
          Session.create!(site: site, fingerprint: 'user2', started_at: Time.current)

          result = AnalyticsEngine.retention(site, cohort_unit: 'month')

          expect(result[:matrix].size).to eq(12)
          expect(result[:cohort_unit]).to eq('month')

          c_1m = result[:matrix].find { |c| c[:cohort] == '2026-06' }
          c_this = result[:matrix].find { |c| c[:cohort] == '2026-07' }

          expect(c_1m[:cohort_size]).to eq(1)
          expect(c_1m[:activity][0]).to eq(100.0)
          expect(c_1m[:activity][1]).to eq(100.0) # active this month
          expect(c_1m[:activity][2]).to be_nil

          expect(c_this[:cohort_size]).to eq(1)
          expect(c_this[:activity][0]).to eq(100.0)
          expect(c_this[:activity][1]).to be_nil
        end
      end
    end
  end
end
