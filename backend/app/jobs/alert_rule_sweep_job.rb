# Re-evaluates every site's alert rules on a fixed cadence, independent of
# incoming event traffic. AlertEvaluationJob only runs when a non-bot event
# arrives (see EventCollector), so a "below" or negative change_rate rule
# watching for traffic dropping to zero can never fire once the events that
# triggered its last evaluation age out of the rolling window: there is no
# later event left to enqueue a re-check. This job closes that gap by
# sweeping every site on its own schedule and rescheduling itself, so
# absence-of-traffic keeps getting evaluated even with zero incoming events.
#
# Bootstrapped once per process by config/initializers/alert_rule_sweep.rb.
# Runs on the default ActiveJob adapter (:async in this app, since no
# persistent queue backend is configured yet) — each self-rescheduled run
# lives only in that process's memory, so a process restart or a multi-worker
# deployment can produce gaps or redundant sweeps. AlertRule#fire! is safe
# under concurrent/duplicate sweeps (see its cooldown re-check under lock),
# so redundancy is wasteful but not incorrect. Moving this to a persistent
# recurring-job backend is tracked as follow-up infra work.
class AlertRuleSweepJob < ApplicationJob
  queue_as :default

  INTERVAL = 5.minutes

  def perform
    Site.where(id: AlertRule.select(:site_id)).find_each do |site|
      AlertRuleEvaluator.perform(site)
    rescue StandardError => e
      Rails.logger.error(
        "[AlertRuleSweepJob] failed to evaluate site_id=#{site.id}: #{e.class}: #{e.message}"
      )
    end
  ensure
    self.class.set(wait: INTERVAL).perform_later
  end
end
