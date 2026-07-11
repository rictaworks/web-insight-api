class AlertRuleEvaluator
  include InternalVitalsFilter

  def self.perform(site)
    new(site).perform
  end

  def initialize(site)
    @site = site
  end

  def perform
    rules = @site.alert_rules.reject(&:cooling_down?)
    return if rules.empty?

    rules.each do |rule|
      val = calculate_metric(rule.metric, rule.condition == 'change_rate')
      rule.fire!(val) if rule.evaluate(val)
    end
  end

  private

  # The current and previous windows must not share their common boundary
  # (now - 24.hours), or an event/session landing exactly on it would count
  # toward both windows and skew the change-rate comparison. The end of the
  # previous window is exclusive (...) so that instant belongs to the current
  # window only.
  def calculate_metric(metric, is_change_rate)
    now = Time.current
    if is_change_rate
      current_val = calculate_metric_value(metric, (now - 24.hours)..now)
      previous_val = calculate_metric_value(metric, (now - 48.hours)...(now - 24.hours))
      calculate_change_rate(current_val, previous_val)
    else
      calculate_metric_value(metric, (now - 24.hours)..now)
    end
  end

  # avg_duration はセッションのみで完結するため、他の指標分岐でのみ events を取得する。
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
  def calculate_metric_value(metric, time_range)
    case metric
    when 'pv'           then fetch_non_bot_events(time_range).count { |e| e.event_type == 'pageview' }
    when 'uv'           then fetch_non_bot_events(time_range).map { |e| e.session.fingerprint }.uniq.size
    when 'session'      then fetch_non_bot_events(time_range).map(&:session_id).uniq.size
    when 'bounce_rate'  then calculate_bounce_rate(fetch_non_bot_events(time_range), time_range)
    when 'avg_duration' then calculate_avg_duration(time_range)
    when 'error_rate'   then calculate_error_rate(fetch_non_bot_events(time_range))
    else 0.0
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity

  def fetch_non_bot_events(time_range)
    events = @site.events
                  .includes(:session)
                  .joins(:session)
                  .where(events: { is_bot: false })
                  .where(sessions: { is_bot: false })
                  .where(occurred_at: time_range)
                  .to_a

    reject_internal_vitals(events)
  end

  def calculate_bounce_rate(events, time_range)
    sessions = fetch_non_bot_sessions(time_range)
    return 0.0 if sessions.empty?

    events_by_session = events.group_by(&:session_id)
    bounce_count = sessions.count do |session|
      session_events = events_by_session[session.id] || []
      session_events.size == 1
    end

    ((bounce_count.to_f / sessions.size) * 100.0).round(2)
  end

  def fetch_non_bot_sessions(time_range)
    sessions = @site.sessions
                    .where(is_bot: false)
                    .where(started_at: time_range)
                    .to_a

    reject_vitals_only_sessions(sessions)
  end

  # started_at/last_seen_at are nullable columns (legacy/imported sessions can
  # carry either as NULL), so a session missing either is excluded from both
  # the sum and the count rather than raising mid-average.
  def calculate_avg_duration(time_range)
    sessions = fetch_non_bot_sessions(time_range)

    durations = sessions.filter_map do |session|
      next if session.started_at.nil? || session.last_seen_at.nil?

      (session.last_seen_at - session.started_at).to_f
    end
    return 0.0 if durations.empty?

    (durations.sum / durations.size).round(2)
  end

  def calculate_error_rate(events)
    return 0.0 if events.empty?

    error_count = count_error_events(events)
    ((error_count.to_f / events.size) * 100.0).round(2)
  end

  def count_error_events(events)
    events.count do |e|
      e.event_type == 'custom' &&
        e.properties.is_a?(Hash) &&
        (e.properties['name'] == 'error' || e.properties.key?('error') || e.properties.key?('error_message'))
    end
  end

  def calculate_change_rate(current, previous)
    return 0.0 if previous.zero? && current.zero?
    return 100.0 if previous.zero?

    (((current - previous).to_f / previous) * 100.0).round(2)
  end
end
