# Kicks off the self-rescheduling AlertRuleSweepJob loop once per server
# process (see app/jobs/alert_rule_sweep_job.rb for why it exists).
#
# Only starts for `bin/rails server` (or its `s` alias) — the one server
# entrypoint this app currently documents (see CLAUDE.md). Any other
# invocation (`rails console`, `rails db:prepare`, the test suite, etc.)
# leaves ARGV.first as something else and is skipped, so those don't each
# spawn their own perpetual sweep chain.
#
# Railway's actual deploy entrypoint is separate, not-yet-done infra work
# (Procfile/deploy config). If that ends up booting the app via a different
# command (e.g. `bundle exec puma` directly instead of `bin/rails server`),
# this guard will need to recognize that entrypoint too.
Rails.application.config.after_initialize do
  next if Rails.env.test?
  next unless %w[server s].include?(ARGV.first)

  AlertRuleSweepJob.perform_later
end
