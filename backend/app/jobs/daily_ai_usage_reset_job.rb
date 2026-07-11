# daily_ai_usage rows are scoped per (site_id, usage_date) with a unique
# index (see db/schema.rb), and used_count defaults to 0. AiRecommendationService
# already creates a fresh row for each new logical date via find_or_create_by!,
# so a new day's quota is available the moment it starts — no explicit
# zeroing is required here.
#
# This job used to also run `DailyAiUsage.where(usage_date: logical_date)
# .update_all(used_count: 0, ...)` at execution time, computed from
# `3.hours.ago.to_date`. Because ActiveJob's :async adapter gives no
# execution-time guarantee, a delayed run past the 03:00 JST boundary could
# recompute `logical_date` as the day that had JUST started (rather than
# the one that just ended) and zero out a row a request had already
# incremented moments earlier, granting an extra recommendation for that
# day. Since resetting is unnecessary for correctness anyway, the safest
# fix is to not do it at all — this job is now pure housekeeping.
class DailyAiUsageResetJob < ApplicationJob
  queue_as :default

  def perform
    DailyAiUsage.where(usage_date: ...30.days.ago.to_date).delete_all
  rescue StandardError => e
    Rails.logger.error("[DailyAiUsageResetJob] cleanup failed: #{e.class}: #{e.message}")
  ensure
    # Runs even if cleanup raises above (e.g. a transient DB error) — this
    # job only exists by virtue of each run enqueueing the next one, so a
    # single failed cleanup must not silently break that chain until the
    # next server boot.
    reschedule
  end

  private

  def reschedule
    next_run = Time.current.change(hour: 3, min: 0, sec: 0)
    next_run += 1.day if next_run <= Time.current
    self.class.set(wait_until: next_run).perform_later
  end
end
