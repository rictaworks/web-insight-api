require 'rails_helper'

RSpec.describe 'Database Schema Integrity', type: :model do
  let(:connection) { ActiveRecord::Base.connection }

  describe 'Table existence and primary keys' do
    let(:expected_tables) do
      %w[
        users sites sessions events web_vitals funnels alert_rules alert_logs
        ai_recommendations daily_ai_usage event_types channel_types
        alert_metric_types cwv_metric_types recommendation_categories age_groups
      ]
    end

    it 'has all expected tables' do
      expected_tables.each do |table_name|
        expect(connection.table_exists?(table_name)).to be(true), "Table #{table_name} does not exist"
      end
    end

    it 'uses string/uuid primary keys for the main tables' do
      main_tables = %w[
        users sites sessions events web_vitals funnels alert_rules alert_logs
        ai_recommendations daily_ai_usage
      ]

      main_tables.each do |table_name|
        pk = connection.primary_key(table_name)
        expect(pk).to eq('id')

        column = connection.columns(table_name).find { |c| c.name == 'id' }
        expect(%i[string uuid]).to include(column.type),
                                   "Table #{table_name} PK should be string/uuid but was #{column.type}"
      end
    end

    it 'uses integer primary keys for lookup tables' do
      lookup_tables = %w[
        event_types channel_types alert_metric_types cwv_metric_types
        recommendation_categories age_groups
      ]

      lookup_tables.each do |table_name|
        pk = connection.primary_key(table_name)
        expect(pk).to eq('id')

        column = connection.columns(table_name).find { |c| c.name == 'id' }
        expect(column.type).to eq(:integer), "Table #{table_name} PK should be integer but was #{column.type}"
      end
    end
  end

  describe 'Model Associations' do
    it 'validates associations without throwing errors' do
      # User <-> Site
      user = User.new(google_sub: 'sub_test', display_name: 'Test')
      expect { user.sites }.not_to raise_error

      site = Site.new(name: 'Test Site', url: 'https://example.com', api_key: 'test_key', user: user)
      expect(site.user).to eq(user)
      expect { site.sessions }.not_to raise_error
      expect { site.events }.not_to raise_error
      expect { site.web_vitals }.not_to raise_error
      expect { site.funnels }.not_to raise_error
      expect { site.alert_rules }.not_to raise_error
      expect { site.ai_recommendations }.not_to raise_error
      expect { site.daily_ai_usages }.not_to raise_error

      # Session <-> Site, Event, WebVital
      session = Session.new(fingerprint: 'fp_test', site: site)
      expect(session.site).to eq(site)
      expect { session.events }.not_to raise_error
      expect { session.web_vitals }.not_to raise_error

      # Event
      event = Event.new(event_type: 'pageview', site: site, session: session)
      expect(event.site).to eq(site)
      expect(event.session).to eq(session)

      # WebVital
      web_vital = WebVital.new(page_url: 'https://example.com', site: site, session: session)
      expect(web_vital.site).to eq(site)
      expect(web_vital.session).to eq(session)

      # Funnel
      funnel = Funnel.new(name: 'Funnel Test', site: site)
      expect(funnel.site).to eq(site)

      # AlertRule <-> AlertLog
      alert_rule = AlertRule.new(metric: 'pv', condition: 'above', threshold: 100, site: site)
      expect(alert_rule.site).to eq(site)
      expect { alert_rule.alert_logs }.not_to raise_error

      # AlertLog
      alert_log = AlertLog.new(fired_at: Time.zone.now, metric_value: 105, alert_rule: alert_rule)
      expect(alert_log.alert_rule).to eq(alert_rule)

      # AiRecommendation
      reco = AiRecommendation.new(category: 'UX', priority: 1, description: 'Fix layout', site: site)
      expect(reco.site).to eq(site)

      # DailyAiUsage
      usage = DailyAiUsage.new(usage_date: Time.zone.today, used_count: 1, site: site)
      expect(usage.site).to eq(site)
    end
  end

  describe 'Seeded Master Data' do
    before do
      Rails.application.load_seed
    end

    it 'has 4 event_types' do
      expect(EventType.count).to eq(4)
      expect(EventType.pluck(:name)).to contain_exactly('pageview', 'click', 'scroll', 'custom')
    end

    it 'has 8 channel_types' do
      expect(ChannelType.count).to eq(8)
      expect(ChannelType.pluck(:name)).to contain_exactly(
        'organic', 'paid', 'referral', 'social', 'email', 'direct', 'display', 'other'
      )
    end

    it 'has 6 alert_metric_types' do
      expect(AlertMetricType.count).to eq(6)
      expect(AlertMetricType.pluck(:name)).to contain_exactly(
        'pv', 'uv', 'session', 'bounce_rate', 'avg_duration', 'error_rate'
      )
    end

    it 'has 5 cwv_metric_types' do
      expect(CwvMetricType.count).to eq(5)
      expect(CwvMetricType.pluck(:name)).to contain_exactly('LCP', 'FID', 'CLS', 'TTFB', 'FCP')
    end

    it 'has 4 recommendation_categories' do
      expect(RecommendationCategory.count).to eq(4)
      expect(RecommendationCategory.pluck(:name)).to contain_exactly('UX', 'SEO', 'パフォーマンス', 'コンテンツ')
    end

    it 'has 6 age_groups' do
      expect(AgeGroup.count).to eq(6)
      expect(AgeGroup.pluck(:name)).to contain_exactly('10代', '20代', '30代', '40代', '50代', '60代以上')
    end
  end
end
