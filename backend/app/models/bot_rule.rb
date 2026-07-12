class BotRule < ApplicationRecord
  validates :pattern, presence: true, uniqueness: true

  # RailsAdmin's generic delete/bulk_delete destroys rows directly, bypassing
  # Admin::BotRulesController's "at least one keyword" guard. Without this,
  # deleting the last row here makes BotDetector.bot_ua_keywords fall back to
  # DEFAULT_BOT_UA_KEYWORDS (see bot_detector.rb), silently re-enabling the
  # built-in filters instead of honoring (or blocking) the admin's change.
  # Enforcing the non-empty invariant here, rather than only in that
  # controller, keeps every mutation path (API, RailsAdmin, console) subject
  # to the same rule.
  before_destroy :prevent_deleting_last_rule

  # BotRule rows can be mutated from two places: the API bulk-update endpoint
  # (Admin::BotRulesController) and RailsAdmin's generic new/edit/delete UI,
  # which bypasses that controller entirely. Invalidating the cache here
  # keeps BotDetector.bot_ua_keywords in sync regardless of which path made
  # the change. after_commit (not after_save/after_destroy) ensures the
  # cache is cleared only once the change is actually visible to other
  # connections, not mid-transaction.
  after_commit :invalidate_bot_ua_keywords_cache

  private

  def prevent_deleting_last_rule
    return if BotRule.where.not(id: id).exists?

    errors.add(:base, :cannot_delete_last_rule)
    throw :abort
  end

  def invalidate_bot_ua_keywords_cache
    Rails.cache.delete('bot_ua_keywords')
  end
end
