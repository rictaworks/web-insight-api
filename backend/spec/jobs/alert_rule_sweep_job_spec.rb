require 'rails_helper'

RSpec.describe AlertRuleSweepJob, type: :job do
  let(:user) { User.create!(google_sub: 'user_123', display_name: 'Alice') }
  let(:site_with_rule) { Site.create!(name: 'Site A', url: 'https://a.example.com', user: user) }
  let(:site_without_rule) { Site.create!(name: 'Site B', url: 'https://b.example.com', user: user) }

  before do
    AlertRule.create!(site: site_with_rule, metric: 'pv', condition: 'below', threshold: 1.0, cooldown_min: 10)
    site_without_rule
    stub_reschedule
  end

  def stub_reschedule
    scheduler = instance_double(ActiveJob::ConfiguredJob, perform_later: true)
    allow(described_class).to receive(:set).with(wait: described_class::INTERVAL).and_return(scheduler)
  end

  it 'evaluates every site that has at least one alert rule' do
    allow(AlertRuleEvaluator).to receive(:perform)

    described_class.perform_now

    expect(AlertRuleEvaluator).to have_received(:perform).with(site_with_rule)
  end

  it 'does not evaluate sites without any alert rules' do
    allow(AlertRuleEvaluator).to receive(:perform)

    described_class.perform_now

    expect(AlertRuleEvaluator).not_to have_received(:perform).with(site_without_rule)
  end

  it 'reschedules itself after the sweep interval regardless of evaluation outcome' do
    allow(AlertRuleEvaluator).to receive(:perform)

    described_class.perform_now

    expect(described_class).to have_received(:set).with(wait: AlertRuleSweepJob::INTERVAL)
  end

  it 'logs and continues evaluating remaining sites when one site raises' do
    other_site = Site.create!(name: 'Site C', url: 'https://c.example.com', user: user)
    AlertRule.create!(site: other_site, metric: 'pv', condition: 'below', threshold: 1.0, cooldown_min: 10)

    allow(AlertRuleEvaluator).to receive(:perform) do |site|
      raise 'boom' if site == site_with_rule
    end
    allow(Rails.logger).to receive(:error)

    expect { described_class.perform_now }.not_to raise_error

    expect(AlertRuleEvaluator).to have_received(:perform).with(other_site)
    expect(Rails.logger).to have_received(:error).with(a_string_matching(/site_id=#{site_with_rule.id}/))
  end
end
