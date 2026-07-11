class AlertRule < ApplicationRecord
  belongs_to :site
  has_many :alert_logs, dependent: :destroy

  VALID_METRICS = %w[pv uv session bounce_rate avg_duration error_rate].freeze
  VALID_CONDITIONS = %w[above below change_rate].freeze

  # threshold は decimal(12,4) 列に収まる範囲（整数部8桁）に、cooldown_min は
  # integer 列（PostgreSQL 4byte 符号付き整数）に収まる範囲に制限する。
  # 範囲外の値はここで 422 として弾かないと、DB 側の桁あふれで save 時に
  # 例外が発生し 500 になってしまう。
  MAX_THRESHOLD = 99_999_999.9999
  MAX_COOLDOWN_MIN = 2_147_483_647

  validates :metric, presence: true, inclusion: { in: VALID_METRICS }
  validates :condition, presence: true, inclusion: { in: VALID_CONDITIONS }
  validates :threshold, presence: true, numericality: {
    greater_than_or_equal_to: -MAX_THRESHOLD, less_than_or_equal_to: MAX_THRESHOLD
  }
  validates :cooldown_min, presence: true, numericality: {
    only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_COOLDOWN_MIN
  }

  # Returns true if the rule is currently in its cooldown window.
  def cooling_down?
    return false if last_fired_at.nil?

    Time.current < last_fired_at + cooldown_min.minutes
  end

  # Returns true if the calculated value violates the threshold.
  # rubocop:disable Naming/PredicateMethod
  def evaluate(val)
    case condition
    when 'above'
      val > threshold
    when 'below'
      val < threshold
    when 'change_rate'
      threshold >= 0 ? val > threshold : val < threshold
    else
      false
    end
  end
  # rubocop:enable Naming/PredicateMethod

  # Fires the alert, writing to alert_logs and updating last_fired_at.
  #
  # /events/collect enqueues an AlertEvaluationJob per non-bot event, so
  # multiple jobs for the same site can evaluate this rule concurrently. Each
  # job checks cooling_down? on its own in-memory copy before calling fire!,
  # which is stale the instant another job commits. with_lock takes a
  # row-level lock (SELECT ... FOR UPDATE) and reloads the record before the
  # block runs, so the cooldown re-check below sees the latest committed
  # last_fired_at and only one concurrent caller can win the race.
  def fire!(val)
    with_lock do
      next if cooling_down?

      alert_logs.create!(
        fired_at: Time.current,
        metric_value: clamp_to_metric_value_range(val)
      )
      update!(last_fired_at: Time.current)
    end
  end

  private

  # alert_logs.metric_value is the same decimal(12,4) column type as
  # threshold. Computed values (e.g. a very high pv/uv/session count, or a
  # large change_rate percentage) are not user input and so were never
  # range-checked; clamp here so a rule that legitimately fired still records
  # a log entry and advances last_fired_at, instead of create! raising and
  # rolling back the write on every retry.
  def clamp_to_metric_value_range(val)
    val.clamp(-MAX_THRESHOLD, MAX_THRESHOLD)
  end
end
