require 'rails_helper'

RSpec.describe DailyAiUsageResetJob, type: :job do
  let(:user) { User.create!(google_sub: 'user_123', display_name: 'Alice') }
  let(:site) { Site.create!(name: 'My Site', url: 'https://example.com', user: user) }

  before do
    stub_reschedule
  end

  def stub_reschedule
    allow(described_class).to receive(:set).and_call_original
  end

  it 'does not touch used_count for a usage row on the current logical date' do
    # Regression test: rows are scoped per (site_id, usage_date) and default
    # to used_count 0 for a fresh date, so this job must not zero out an
    # existing row for "today" — doing so at execution time (rather than at
    # the scheduled 03:00 boundary) could wipe out a recommendation already
    # made in the brand-new logical day, granting an extra one.
    logical_date = 3.hours.ago.to_date
    usage = site.daily_ai_usages.create!(usage_date: logical_date, used_count: 1)

    described_class.perform_now

    expect(usage.reload.used_count).to eq(1)
    expect(usage.reset_at).to be_nil
  end

  it 'cleans up usage records older than 30 days' do
    old_date = 31.days.ago.to_date
    recent_date = 29.days.ago.to_date

    old_usage = site.daily_ai_usages.create!(usage_date: old_date, used_count: 1)
    recent_usage = site.daily_ai_usages.create!(usage_date: recent_date, used_count: 1)

    described_class.perform_now

    expect(DailyAiUsage.exists?(old_usage.id)).to be false
    expect(DailyAiUsage.exists?(recent_usage.id)).to be true
  end

  it 'reschedules itself for tomorrow at JST 03:00' do
    # Time.current change for tomorrow JST 03:00
    next_run = Time.current.change(hour: 3, min: 0, sec: 0)
    next_run += 1.day if next_run <= Time.current

    # We expect `described_class.set(wait_until: next_run)` to be called and return a configured job
    scheduler = instance_double(ActiveJob::ConfiguredJob, perform_later: true)
    expect(described_class).to receive(:set).with(wait_until: next_run).and_return(scheduler)

    described_class.perform_now
  end

  it 'still reschedules itself when the cleanup query raises' do
    # Regression test: this job only exists by virtue of each run enqueueing
    # the next one, so a single transient failure (e.g. a DB error) must not
    # break that chain until the next server boot.
    allow(DailyAiUsage).to receive(:where).and_raise(ActiveRecord::StatementInvalid.new('boom'))
    allow(Rails.logger).to receive(:error)

    scheduler = instance_double(ActiveJob::ConfiguredJob, perform_later: true)
    allow(described_class).to receive(:set).and_return(scheduler)

    expect { described_class.perform_now }.not_to raise_error

    expect(described_class).to have_received(:set)
    expect(Rails.logger).to have_received(:error).with(a_string_matching(/cleanup failed/))
  end
end
