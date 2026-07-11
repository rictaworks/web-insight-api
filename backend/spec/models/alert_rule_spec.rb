require 'rails_helper'

RSpec.describe AlertRule, type: :model do
  let(:user) { User.create!(google_sub: 'user_123', display_name: 'Alice') }
  let(:site) { Site.create!(name: 'Alice Site', url: 'https://alicesite.com', user: user) }

  describe 'Validations' do
    it 'is valid with valid attributes' do
      rule = AlertRule.new(
        site: site,
        metric: 'pv',
        condition: 'above',
        threshold: 100.0,
        cooldown_min: 30
      )
      expect(rule).to be_valid
    end

    it 'is invalid with an unsupported metric' do
      rule = AlertRule.new(site: site, metric: 'invalid_metric', condition: 'above', threshold: 10.0)
      expect(rule).not_to be_valid
      expect(rule.errors[:metric]).to include('is not included in the list')
    end

    it 'is invalid with an unsupported condition' do
      rule = AlertRule.new(site: site, metric: 'pv', condition: 'invalid_condition', threshold: 10.0)
      expect(rule).not_to be_valid
      expect(rule.errors[:condition]).to include('is not included in the list')
    end

    it 'is invalid with a non-numeric threshold' do
      rule = AlertRule.new(site: site, metric: 'pv', condition: 'above', threshold: 'ten')
      expect(rule).not_to be_valid
      expect(rule.errors[:threshold]).to include('is not a number')
    end

    it 'is invalid with a negative cooldown_min' do
      rule = AlertRule.new(site: site, metric: 'pv', condition: 'above', threshold: 10.0, cooldown_min: -5)
      expect(rule).not_to be_valid
      expect(rule.errors[:cooldown_min]).to include('must be greater than or equal to 0')
    end

    it 'is invalid with a threshold that exceeds the decimal(12,4) column range' do
      rule = AlertRule.new(site: site, metric: 'pv', condition: 'above', threshold: 100_000_000.0, cooldown_min: 10)
      expect(rule).not_to be_valid
      expect(rule.errors[:threshold]).to include('must be less than or equal to 99999999.9999')
    end

    it 'is invalid with a threshold below the decimal(12,4) column range' do
      rule = AlertRule.new(site: site, metric: 'pv', condition: 'above', threshold: -100_000_000.0, cooldown_min: 10)
      expect(rule).not_to be_valid
      expect(rule.errors[:threshold]).to include('must be greater than or equal to -99999999.9999')
    end

    it 'is invalid with a cooldown_min that exceeds the integer column range' do
      rule = AlertRule.new(site: site, metric: 'pv', condition: 'above', threshold: 10.0, cooldown_min: 99_999_999_999)
      expect(rule).not_to be_valid
      expect(rule.errors[:cooldown_min]).to include('must be less than or equal to 2147483647')
    end

    it 'is valid at the boundary of the allowed threshold and cooldown_min ranges' do
      rule = AlertRule.new(
        site: site,
        metric: 'pv',
        condition: 'above',
        threshold: AlertRule::MAX_THRESHOLD,
        cooldown_min: AlertRule::MAX_COOLDOWN_MIN
      )
      expect(rule).to be_valid
    end
  end

  describe '#cooling_down?' do
    let(:rule) { AlertRule.create!(site: site, metric: 'pv', condition: 'above', threshold: 10.0, cooldown_min: 30) }

    it 'returns false if last_fired_at is nil' do
      expect(rule.cooling_down?).to be(false)
    end

    it 'returns true if last_fired_at is within cooldown period' do
      rule.update!(last_fired_at: 10.minutes.ago)
      expect(rule.cooling_down?).to be(true)
    end

    it 'returns false if last_fired_at is outside cooldown period' do
      rule.update!(last_fired_at: 40.minutes.ago)
      expect(rule.cooling_down?).to be(false)
    end
  end

  describe '#evaluate' do
    context 'when condition is above' do
      let(:rule) { AlertRule.new(site: site, metric: 'pv', condition: 'above', threshold: 10.0) }

      it 'returns true if value is above threshold' do
        expect(rule.evaluate(15.0)).to be(true)
      end

      it 'returns false if value is equal or below threshold' do
        expect(rule.evaluate(10.0)).to be(false)
        expect(rule.evaluate(5.0)).to be(false)
      end
    end

    context 'when condition is below' do
      let(:rule) { AlertRule.new(site: site, metric: 'pv', condition: 'below', threshold: 10.0) }

      it 'returns true if value is below threshold' do
        expect(rule.evaluate(5.0)).to be(true)
      end

      it 'returns false if value is equal or above threshold' do
        expect(rule.evaluate(10.0)).to be(false)
        expect(rule.evaluate(15.0)).to be(false)
      end
    end

    context 'when condition is change_rate' do
      context 'with a positive threshold' do
        let(:rule) { AlertRule.new(site: site, metric: 'pv', condition: 'change_rate', threshold: 50.0) }

        it 'returns true if change rate is above threshold' do
          expect(rule.evaluate(60.0)).to be(true)
        end

        it 'returns false if change rate is at or below threshold' do
          expect(rule.evaluate(50.0)).to be(false)
          expect(rule.evaluate(30.0)).to be(false)
        end
      end

      context 'with a negative threshold' do
        let(:rule) { AlertRule.new(site: site, metric: 'pv', condition: 'change_rate', threshold: -30.0) }

        it 'returns true if change rate is below threshold' do
          expect(rule.evaluate(-40.0)).to be(true)
        end

        it 'returns false if change rate is at or above threshold' do
          expect(rule.evaluate(-30.0)).to be(false)
          expect(rule.evaluate(-10.0)).to be(false)
        end
      end
    end
  end

  describe '#fire!' do
    let(:rule) { AlertRule.create!(site: site, metric: 'pv', condition: 'above', threshold: 10.0, cooldown_min: 30) }

    it 'creates an AlertLog entry and updates last_fired_at' do
      expect do
        rule.fire!(15.5)
      end.to change(AlertLog, :count).by(1)

      expect(rule.last_fired_at).to be_within(1.second).of(Time.current)
      log = rule.alert_logs.last
      expect(log.metric_value).to eq(15.5)
      expect(log.fired_at).to be_within(1.second).of(Time.current)
    end

    it 'clamps a computed value exceeding the decimal(12,4) alert_logs column range instead of raising' do
      # A computed metric (e.g. a very high pv count or a large change_rate
      # percentage) is not user input and so was never range-checked; without
      # clamping, create! raises and rolls back before last_fired_at updates,
      # so every later evaluation retries and fails the same way.
      expect do
        rule.fire!(500_000_000.0)
      end.to change(AlertLog, :count).by(1)

      expect(rule.reload.last_fired_at).to be_within(1.second).of(Time.current)
      expect(rule.alert_logs.last.metric_value).to eq(AlertRule::MAX_THRESHOLD)
    end

    it 'clamps a computed value below the negative decimal(12,4) alert_logs column range instead of raising' do
      expect do
        rule.fire!(-500_000_000.0)
      end.to change(AlertLog, :count).by(1)

      expect(rule.alert_logs.last.metric_value).to eq(-AlertRule::MAX_THRESHOLD)
    end

    it 'does not create a second AlertLog when fired again before the cooldown elapses' do
      # Regression test for a race between concurrent AlertEvaluationJob runs:
      # each job reads cooling_down? on its own copy of the rule before
      # calling fire!, so two jobs racing on the same rule could both pass
      # that check and both call fire! before either commits. Calling fire!
      # twice back-to-back on the same in-memory rule reproduces the second
      # job's call after the first job's write has landed, and must be a
      # no-op rather than a duplicate alert_log.
      rule.fire!(15.5)

      expect do
        rule.fire!(16.0)
      end.not_to change(AlertLog, :count)
    end
  end
end
