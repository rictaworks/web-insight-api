require 'rails_helper'

RSpec.describe AnalyticsEngine, type: :service do
  let(:user) { User.create!(google_sub: 'user_123', display_name: 'Alice') }
  let(:site) { Site.create!(name: 'My Site', url: 'https://mysite.com', user: user) }

  before do
    Rails.cache.clear
  end

  describe '.funnel' do
    let(:funnel) do
      Funnel.create!(
        name: 'Purchase Funnel',
        site: site,
        steps: ['/', '/products', '/cart', '/checkout']
      )
    end

    it 'caches the result for 5 minutes' do
      expect(Rails.cache).to receive(:fetch).with("funnel_#{site.id}_#{funnel.id}_30d",
                                                  expires_in: 5.minutes).and_call_original
      AnalyticsEngine.funnel(site, funnel, period: '30d')
    end

    context 'with pageview events' do
      let!(:session_complete) { Session.create!(site: site, fingerprint: 'fp_complete', started_at: 5.days.ago) }
      let!(:session_partial) { Session.create!(site: site, fingerprint: 'fp_partial', started_at: 5.days.ago) }
      let!(:session_no_start) { Session.create!(site: site, fingerprint: 'fp_no_start', started_at: 5.days.ago) }
      let!(:session_out_of_order) { Session.create!(site: site, fingerprint: 'fp_ooo', started_at: 5.days.ago) }
      let!(:bot_session) { Session.create!(site: site, fingerprint: 'fp_bot', is_bot: true, started_at: 5.days.ago) }

      before do
        # 1. Complete Session: visits / -> /products -> /cart -> /checkout
        Event.create!(site: site, session: session_complete, event_type: 'pageview', page_url: 'https://mysite.com/',
                      occurred_at: 10.days.ago, is_bot: false)
        Event.create!(site: site, session: session_complete, event_type: 'pageview',
                      page_url: 'https://mysite.com/products/', occurred_at: 9.days.ago, is_bot: false)
        Event.create!(site: site, session: session_complete, event_type: 'pageview',
                      page_url: 'https://mysite.com/cart', occurred_at: 8.days.ago, is_bot: false)
        Event.create!(site: site, session: session_complete, event_type: 'pageview',
                      page_url: 'https://mysite.com/checkout', occurred_at: 7.days.ago, is_bot: false)

        # 2. Partial Session: visits / -> /products (drops off here)
        Event.create!(site: site, session: session_partial, event_type: 'pageview', page_url: '/',
                      occurred_at: 10.days.ago, is_bot: false)
        # Testing exact path match with relative path and trailing slash too
        Event.create!(site: site, session: session_partial, event_type: 'pageview', page_url: '/products/',
                      occurred_at: 9.days.ago, is_bot: false)

        # 3. No Start Session: visits /products -> /cart (never visited step 1)
        Event.create!(site: site, session: session_no_start, event_type: 'pageview', page_url: '/products',
                      occurred_at: 10.days.ago, is_bot: false)
        Event.create!(site: site, session: session_no_start, event_type: 'pageview', page_url: '/cart',
                      occurred_at: 9.days.ago, is_bot: false)

        # 4. Out-of-order session: /products (10d) -> / (9d) -> /cart (8d).
        # Step 0 matches '/' at 9d. Step 1 needs '/products' at/after 9d, but its
        # only '/products' visit was at 10d, so Step 1 never matches and Step 2 is
        # not reached. Contributes to Step 0 only.
        Event.create!(site: site, session: session_out_of_order, event_type: 'pageview', page_url: '/products',
                      occurred_at: 10.days.ago, is_bot: false)
        Event.create!(site: site, session: session_out_of_order, event_type: 'pageview', page_url: '/',
                      occurred_at: 9.days.ago, is_bot: false)
        Event.create!(site: site, session: session_out_of_order, event_type: 'pageview', page_url: '/cart',
                      occurred_at: 8.days.ago, is_bot: false)

        # 5. Bot Session: visits / -> /products -> /cart -> /checkout (should be ignored)
        Event.create!(site: site, session: bot_session, event_type: 'pageview', page_url: '/',
                      occurred_at: 10.days.ago, is_bot: false)

        # 6. Bot Event on normal session (should be ignored)
        bot_event_session = Session.create!(site: site, fingerprint: 'fp_bot_evt', started_at: 5.days.ago)
        Event.create!(site: site, session: bot_event_session, event_type: 'pageview', page_url: '/',
                      occurred_at: 10.days.ago, is_bot: true)
      end

      it 'calculates passing counts, drop-offs, drop-off rates and completion rate correctly' do
        result = AnalyticsEngine.funnel(site, funnel, period: '30d')

        expect(result[:id]).to eq(funnel.id)
        expect(result[:name]).to eq(funnel.name)

        steps = result[:steps]
        expect(steps.size).to eq(4)

        # Step 1: '/'
        # session_complete, session_partial, session_out_of_order (visits '/' at 9.days.ago) should match.
        # Total = 3
        expect(steps[0][:step_number]).to eq(1)
        expect(steps[0][:type]).to eq('url')
        expect(steps[0][:value]).to eq('/')
        expect(steps[0][:count]).to eq(3)
        # 3 started, 2 went to Step 2 (/products) -> drop_off = 1
        expect(steps[0][:drop_off]).to eq(1)
        expect(steps[0][:drop_off_rate]).to eq(33.33)

        # Step 2: '/products'
        # session_complete (9.days.ago >= 10.days.ago), session_partial (9.days.ago >= 10.days.ago) should match.
        # session_out_of_order visited /products at 10d but '/' at 9d, so it
        # cannot match '/products' at/after 9d.
        # Total = 2
        expect(steps[1][:step_number]).to eq(2)
        expect(steps[1][:value]).to eq('/products')
        expect(steps[1][:count]).to eq(2)
        # 2 entered Step 2, 1 went to Step 3 (/cart) -> drop_off = 1
        expect(steps[1][:drop_off]).to eq(1)
        expect(steps[1][:drop_off_rate]).to eq(50.0)

        # Step 3: '/cart'
        # session_complete (8.days.ago >= 9.days.ago) matches.
        # Total = 1
        expect(steps[2][:step_number]).to eq(3)
        expect(steps[2][:value]).to eq('/cart')
        expect(steps[2][:count]).to eq(1)
        # 1 entered Step 3, 1 went to Step 4 (/checkout) -> drop_off = 0
        expect(steps[2][:drop_off]).to eq(0)
        expect(steps[2][:drop_off_rate]).to eq(0.0)

        # Step 4: '/checkout'
        # session_complete (7.days.ago >= 8.days.ago) matches.
        # Total = 1
        expect(steps[3][:step_number]).to eq(4)
        expect(steps[3][:value]).to eq('/checkout')
        expect(steps[3][:count]).to eq(1)
        expect(steps[3][:drop_off]).to eq(0)
        expect(steps[3][:drop_off_rate]).to eq(0.0)

        # Completion rate: (1 / 3) * 100 = 33.33%
        expect(result[:completion_rate]).to eq(33.33)
      end

      it 'ignores events outside the specified period' do
        # Create events for a session, but one of them is outside the 7-day period
        session_out = Session.create!(site: site, fingerprint: 'fp_out', started_at: 15.days.ago)
        # With period = 7d, current period starts 6 days ago. 10 days ago is outside!
        Event.create!(site: site, session: session_out, event_type: 'pageview', page_url: '/',
                      occurred_at: 10.days.ago, is_bot: false)
        Event.create!(site: site, session: session_out, event_type: 'pageview', page_url: '/products',
                      occurred_at: 2.days.ago, is_bot: false)

        # In 7d, '/' event is not found for this session, so count for step 1 should exclude it.
        result = AnalyticsEngine.funnel(site, funnel, period: '7d')
        # In the 7d window no session has a '/' event (all are ~10d old), so the
        # funnel entry step (step 1) counts zero.
        expect(result[:steps][0][:count]).to eq(0)
      end
    end

    context 'with event-based steps' do
      let(:event_funnel) do
        Funnel.create!(
          name: 'Engagement Funnel',
          site: site,
          steps: [{ type: 'url', value: '/' }, { type: 'event', value: 'click' }]
        )
      end

      let!(:session_clicked) { Session.create!(site: site, fingerprint: 'fp_click', started_at: 5.days.ago) }
      let!(:session_no_click) { Session.create!(site: site, fingerprint: 'fp_noclick', started_at: 5.days.ago) }

      before do
        # Session that lands on '/' then fires a click event -> completes both steps.
        Event.create!(site: site, session: session_clicked, event_type: 'pageview', page_url: '/',
                      occurred_at: 10.days.ago, is_bot: false)
        Event.create!(site: site, session: session_clicked, event_type: 'click', page_url: '/',
                      occurred_at: 9.days.ago, is_bot: false)

        # Session that lands on '/' but never clicks -> drops off at step 2.
        Event.create!(site: site, session: session_no_click, event_type: 'pageview', page_url: '/',
                      occurred_at: 10.days.ago, is_bot: false)
      end

      it 'counts sessions that fired the configured event' do
        result = AnalyticsEngine.funnel(site, event_funnel, period: '30d')

        steps = result[:steps]
        expect(steps.size).to eq(2)

        expect(steps[0][:type]).to eq('url')
        expect(steps[0][:count]).to eq(2)

        expect(steps[1][:type]).to eq('event')
        expect(steps[1][:value]).to eq('click')
        expect(steps[1][:count]).to eq(1)

        expect(result[:completion_rate]).to eq(50.0)
      end
    end
  end

  describe '.normalize_path' do
    it 'normalizes full URLs to paths' do
      expect(AnalyticsEngine.normalize_path('https://mysite.com/products')).to eq('/products')
      expect(AnalyticsEngine.normalize_path('http://example.org:3000/cart/')).to eq('/cart')
    end

    it 'normalizes relative paths' do
      expect(AnalyticsEngine.normalize_path('/products/')).to eq('/products')
      expect(AnalyticsEngine.normalize_path('/')).to eq('/')
    end

    it 'handles query strings and hashes' do
      expect(AnalyticsEngine.normalize_path('https://mysite.com/products?ref=123#tab-1')).to eq('/products')
      expect(AnalyticsEngine.normalize_path('/cart?checkout=true')).to eq('/cart')
    end

    it 'returns empty string for blank values' do
      expect(AnalyticsEngine.normalize_path('')).to eq('')
      expect(AnalyticsEngine.normalize_path(nil)).to eq('')
    end
  end
end
