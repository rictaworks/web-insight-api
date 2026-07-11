# config/initializers/daily_ai_usage_reset.rb
# Kicks off the self-rescheduling DailyAiUsageResetJob loop once per server
# process at the next JST 03:00 boundary.
#
# Only starts for `bin/rails server` (or its `s` alias) - similar to the alert rules sweep.
Rails.application.config.after_initialize do
  next if Rails.env.test?
  next unless %w[server s].include?(ARGV.first)

  now = Time.current
  next_run = now.change(hour: 3, min: 0, sec: 0)
  next_run += 1.day if next_run <= now

  DailyAiUsageResetJob.set(wait_until: next_run).perform_later
end
