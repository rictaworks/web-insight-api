# rubocop:disable Metrics/ClassLength, Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
class AnalyticsEngine
  CACHE_TTL = 5.minutes

  def self.pageviews(site, period:, axis:)
    cache_key = "pageviews_#{site.id}_#{period}_#{axis}"

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      new(site, period: period, axis: axis).calculate_pageviews
    end
  end

  def self.heatmap(site, url:, viewport:)
    cache_key = "heatmap_#{site.id}_#{url}_#{viewport}"

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      new(site, period: nil, axis: nil).calculate_heatmap(url: url, viewport: viewport)
    end
  end

  def self.mobile_user_agent?(user_agent)
    return false if user_agent.blank?

    user_agent.match?(/Mobi|Android|iPhone|iPad|Windows Phone/i)
  end

  def initialize(site, period:, axis:)
    @site = site
    @period = period
    @axis = axis
  end

  def calculate_pageviews
    now = Time.current
    current_start, current_end, previous_start, previous_end = calculate_ranges(now, @period)

    # Fetch events for current period (excluding bots).
    # A session may be classified as a bot after its first event was stored with
    # events.is_bot=false, so both the event flag and the session flag are excluded.
    current_events = @site.events
                          .joins(:session)
                          .where(events: { is_bot: false })
                          .where(sessions: { is_bot: false })
                          .where(occurred_at: current_start..current_end)
                          .select(
                            'events.id, events.event_type, events.session_id, ' \
                            'events.occurred_at, sessions.fingerprint'
                          ).to_a

    # Fetch events for previous period (excluding bots; see note above on session flag)
    previous_events = @site.events
                           .joins(:session)
                           .where(events: { is_bot: false })
                           .where(sessions: { is_bot: false })
                           .where(occurred_at: previous_start...previous_end)
                           .select('events.id, events.event_type, events.session_id, sessions.fingerprint')
                           .to_a

    # Totals for current period
    current_pv = current_events.count { |e| e.event_type == 'pageview' }
    current_uv = current_events.map(&:fingerprint).uniq.size
    current_session = current_events.map(&:session_id).uniq.size

    # Totals for previous period
    previous_pv = previous_events.count { |e| e.event_type == 'pageview' }
    previous_uv = previous_events.map(&:fingerprint).uniq.size
    previous_session = previous_events.map(&:session_id).uniq.size

    # Change rates
    change_rates = {
      pv: calculate_change_rate(current_pv, previous_pv),
      uv: calculate_change_rate(current_uv, previous_uv),
      session: calculate_change_rate(current_session, previous_session)
    }

    # Generate labels
    labels = generate_labels(current_start, current_end, @axis)

    # Group current events by label (grouped by the JST timezone representation)
    grouped_events = current_events.group_by do |event|
      time = event.occurred_at.in_time_zone
      case @axis
      when 'day'
        time.strftime('%Y-%m-%d')
      when 'week'
        time.beginning_of_week.strftime('%Y-%m-%d')
      when 'month'
        time.strftime('%Y-%m')
      end
    end

    # Build series
    series = labels.map do |label|
      events_for_label = grouped_events[label] || []
      {
        label: label,
        pv: events_for_label.count { |e| e.event_type == 'pageview' },
        uv: events_for_label.map(&:fingerprint).uniq.size,
        session: events_for_label.map(&:session_id).uniq.size
      }
    end

    {
      totals: {
        pv: current_pv,
        uv: current_uv,
        session: current_session
      },
      change_rates: change_rates,
      series: series
    }
  end

  def calculate_heatmap(url:, viewport:)
    clicks = @site.events
                  .joins(:session)
                  .where(events: { event_type: 'click', page_url: url, is_bot: false })
                  .where(sessions: { is_bot: false })
                  .select('events.x_ratio, events.y_ratio, events.user_agent')
                  .to_a

    filtered_clicks = clicks.select do |c|
      is_mobile = self.class.mobile_user_agent?(c.user_agent)
      viewport == 'mobile' ? is_mobile : !is_mobile
    end

    grid_size = 20
    grid = Array.new(grid_size) { Array.new(grid_size, 0) }
    max_count = 0

    filtered_clicks.each do |c|
      next if c.x_ratio.nil? || c.y_ratio.nil?

      col = (c.x_ratio.to_f * grid_size).floor
      row = (c.y_ratio.to_f * grid_size).floor

      col = col.clamp(0, grid_size - 1)
      row = row.clamp(0, grid_size - 1)

      grid[row][col] += 1
      max_count = grid[row][col] if grid[row][col] > max_count
    end

    {
      grid: grid,
      max_count: max_count
    }
  end

  private

  def calculate_ranges(now, period)
    days = case period
           when '7d' then 7
           when '30d' then 30
           when '90d' then 90
           else raise ArgumentError, "Invalid period: #{period}"
           end

    current_start = (days - 1).days.ago(now).beginning_of_day
    current_end = now

    previous_start = current_start - days.days
    previous_end = current_start

    [current_start, current_end, previous_start, previous_end]
  end

  def generate_labels(start_time, end_time, axis)
    labels = []
    case axis
    when 'day'
      t = start_time.to_date
      while t <= end_time.to_date
        labels << t.strftime('%Y-%m-%d')
        t += 1.day
      end
    when 'week'
      t = start_time.to_date.beginning_of_week
      while t <= end_time.to_date
        labels << t.strftime('%Y-%m-%d')
        t += 1.week
      end
      labels.uniq!
    when 'month'
      t = start_time.to_date.beginning_of_month
      while t <= end_time.to_date
        labels << t.strftime('%Y-%m')
        t += 1.month
      end
      labels.uniq!
    else
      raise ArgumentError, "Invalid axis: #{axis}"
    end
    labels
  end

  def calculate_change_rate(current, previous)
    if previous.positive?
      ((current - previous) / previous.to_f * 100).round(2)
    else
      current.positive? ? 100.0 : 0.0
    end
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
