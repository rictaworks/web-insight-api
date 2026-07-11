require 'rails_helper'

RSpec.describe AlertRuleEvaluator, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(google_sub: 'user_123', display_name: 'Alice') }
  let(:site) { Site.create!(name: 'Alice Site', url: 'https://alicesite.com', user: user) }

  # Helper to create a session
  def create_session(fingerprint, is_bot: false, started_at: Time.current, last_seen_at: Time.current)
    Session.create!(
      site: site,
      fingerprint: fingerprint,
      channel: 'direct',
      is_bot: is_bot,
      started_at: started_at,
      last_seen_at: last_seen_at
    )
  end

  # Helper to create an event
  def create_event(session, event_type: 'pageview', occurred_at: Time.current, is_bot: false, properties: {})
    Event.create!(
      site: site,
      session: session,
      event_type: event_type,
      occurred_at: occurred_at,
      is_bot: is_bot,
      properties: properties
    )
  end

  describe '#perform' do
    context 'when evaluating pageviews (pv)' do
      let!(:pv_rule) do
        AlertRule.create!(site: site, metric: 'pv', condition: 'above', threshold: 2.0, cooldown_min: 10)
      end

      it 'fires alert if pageviews exceed threshold' do
        session = create_session('fp1')
        create_event(session, occurred_at: 5.minutes.ago)
        create_event(session, occurred_at: 2.minutes.ago)
        create_event(session, occurred_at: 1.minute.ago)

        expect do
          AlertRuleEvaluator.perform(site)
        end.to change(AlertLog, :count).by(1)

        expect(pv_rule.reload.last_fired_at).to be_present
      end

      it 'does not fire alert if pageviews do not exceed threshold' do
        session = create_session('fp1')
        create_event(session, occurred_at: 5.minutes.ago)
        create_event(session, occurred_at: 2.minutes.ago)

        expect do
          AlertRuleEvaluator.perform(site)
        end.not_to change(AlertLog, :count)
      end

      it 'ignores bot traffic' do
        session = create_session('fp1', is_bot: false)
        bot_session = create_session('fp2', is_bot: true)

        create_event(session, occurred_at: 5.minutes.ago)
        create_event(session, occurred_at: 2.minutes.ago)
        create_event(bot_session, occurred_at: 1.minute.ago, is_bot: true)

        expect do
          AlertRuleEvaluator.perform(site)
        end.not_to change(AlertLog, :count)
      end

      it 'ignores internal vitals events' do
        session = create_session('fp1')
        create_event(session, occurred_at: 5.minutes.ago)
        create_event(session, occurred_at: 2.minutes.ago)
        create_event(session, event_type: 'custom', occurred_at: 1.minute.ago, properties: { 'wia_vitals' => true })

        expect do
          AlertRuleEvaluator.perform(site)
        end.not_to change(AlertLog, :count)
      end

      it 'skips evaluation if rule is cooling down' do
        pv_rule.update!(last_fired_at: 5.minutes.ago)

        session = create_session('fp1')
        create_event(session, occurred_at: 5.minutes.ago)
        create_event(session, occurred_at: 2.minutes.ago)
        create_event(session, occurred_at: 1.minute.ago)

        expect do
          AlertRuleEvaluator.perform(site)
        end.not_to change(AlertLog, :count)
      end
    end

    context 'when evaluating unique users (uv)' do
      let!(:uv_rule) do
        AlertRule.create!(site: site, metric: 'uv', condition: 'above', threshold: 1.0, cooldown_min: 10)
      end

      it 'fires alert if uv exceeds threshold' do
        s1 = create_session('fp1')
        s2 = create_session('fp2')
        create_event(s1)
        create_event(s2)

        expect do
          AlertRuleEvaluator.perform(site)
        end.to change(AlertLog, :count).by(1)
      end
    end

    context 'when evaluating sessions' do
      let!(:session_rule) do
        AlertRule.create!(site: site, metric: 'session', condition: 'above', threshold: 1.0, cooldown_min: 10)
      end

      it 'fires alert if session count exceeds threshold' do
        s1 = create_session('fp1')
        s2 = create_session('fp2')
        create_event(s1)
        create_event(s2)

        expect do
          AlertRuleEvaluator.perform(site)
        end.to change(AlertLog, :count).by(1)
      end
    end

    context 'when evaluating bounce rate' do
      let!(:bounce_rule) do
        AlertRule.create!(site: site, metric: 'bounce_rate', condition: 'above', threshold: 60.0, cooldown_min: 10)
      end

      it 'fires alert if bounce rate exceeds threshold' do
        s1 = create_session('fp1')
        s2 = create_session('fp2')
        create_event(s1)
        create_event(s2)
        create_event(s2, event_type: 'click')

        expect do
          AlertRuleEvaluator.perform(site)
        end.not_to change(AlertLog, :count)

        s3 = create_session('fp3')
        create_event(s3)

        expect do
          AlertRuleEvaluator.perform(site)
        end.to change(AlertLog, :count).by(1)
      end

      it 'excludes vitals-only sessions from the bounce rate denominator' do
        # 2 bounces / 3 real sessions = 66.67% (above the 60% threshold), but a
        # vitals-only session in the denominator would dilute it to 50% and
        # miss the alert (2 / 4).
        s1 = create_session('fp1')
        create_event(s1)

        s2 = create_session('fp2')
        create_event(s2)

        s3 = create_session('fp3')
        create_event(s3)
        create_event(s3, event_type: 'click')

        vitals_session = create_session('fp4')
        create_event(vitals_session, event_type: 'custom', properties: { 'wia_vitals' => true })

        expect do
          AlertRuleEvaluator.perform(site)
        end.to change(AlertLog, :count).by(1)
      end
    end

    context 'when evaluating average duration' do
      let!(:duration_rule) do
        AlertRule.create!(site: site, metric: 'avg_duration', condition: 'above', threshold: 100.0, cooldown_min: 10)
      end

      it 'fires alert if average duration exceeds threshold' do
        s1 = create_session('fp1', started_at: 200.seconds.ago, last_seen_at: Time.current)
        create_event(s1)

        expect do
          AlertRuleEvaluator.perform(site)
        end.to change(AlertLog, :count).by(1)
      end

      it 'excludes vitals-only sessions from the average duration calculation' do
        # A real session lasting 150s averages above the 100s threshold alone,
        # but a ~0s vitals-only session in the mix would drag the average down
        # to 75s and miss the alert.
        s1 = create_session('fp1', started_at: 150.seconds.ago, last_seen_at: Time.current)
        create_event(s1)

        vitals_session = create_session('fp2')
        create_event(vitals_session, event_type: 'custom', properties: { 'wia_vitals' => true })

        expect do
          AlertRuleEvaluator.perform(site)
        end.to change(AlertLog, :count).by(1)
      end

      it 'skips sessions with a missing last_seen_at instead of raising' do
        # last_seen_at is a nullable column, so a legacy/imported session can
        # carry NULL there. Subtracting nil used to raise and abort the whole
        # AlertEvaluationJob; such sessions must be excluded from the average
        # instead.
        s1 = create_session('fp1', started_at: 150.seconds.ago, last_seen_at: Time.current)
        create_event(s1)

        incomplete_session = create_session('fp2', started_at: 150.seconds.ago, last_seen_at: nil)
        create_event(incomplete_session)

        expect do
          AlertRuleEvaluator.perform(site)
        end.not_to raise_error

        expect(AlertLog.count).to eq(1)
      end

      it 'does not query events for a duration-only rule' do
        # avg_duration is computed entirely from sessions, so loading every
        # non-bot event in the window for a duration-only rule is wasted work
        # on every AlertEvaluationJob run for a busy site.
        s1 = create_session('fp1', started_at: 200.seconds.ago, last_seen_at: Time.current)
        create_event(s1)

        expect_any_instance_of(AlertRuleEvaluator).not_to receive(:fetch_non_bot_events)

        AlertRuleEvaluator.perform(site)
      end
    end

    context 'when evaluating error rate' do
      let!(:error_rule) do
        AlertRule.create!(site: site, metric: 'error_rate', condition: 'above', threshold: 20.0, cooldown_min: 10)
      end

      it 'fires alert if error rate exceeds threshold' do
        session = create_session('fp1')
        create_event(session)
        create_event(session, event_type: 'click')
        create_event(session, event_type: 'custom', properties: { 'name' => 'error' })

        expect do
          AlertRuleEvaluator.perform(site)
        end.to change(AlertLog, :count).by(1)
      end
    end

    context 'when evaluating change rate' do
      let!(:change_rule) do
        AlertRule.create!(site: site, metric: 'pv', condition: 'change_rate', threshold: 50.0, cooldown_min: 10)
      end

      it 'fires alert if change rate compared to previous 24h exceeds threshold' do
        session = create_session('fp1')

        create_event(session, occurred_at: 30.hours.ago)
        create_event(session, occurred_at: 28.hours.ago)

        create_event(session, occurred_at: 5.hours.ago)
        create_event(session, occurred_at: 4.hours.ago)
        create_event(session, occurred_at: 3.hours.ago)
        create_event(session, occurred_at: 2.hours.ago)

        expect do
          AlertRuleEvaluator.perform(site)
        end.to change(AlertLog, :count).by(1)
      end

      it 'does not double count an event exactly on the current/previous window boundary' do
        # The current window is (now-24h .. now] and the previous window is
        # (now-48h .. now-24h). An event landing exactly on the shared
        # now-24h instant must count in the current window only; counting it
        # in both would understate the change rate.
        freeze_time do
          session = create_session('fp1')
          create_event(session, occurred_at: 24.hours.ago)

          expect do
            AlertRuleEvaluator.perform(site)
          end.to change(AlertLog, :count).by(1)

          expect(AlertLog.last.metric_value).to eq(100.0)
        end
      end
    end
  end
end
