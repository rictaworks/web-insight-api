# rubocop:disable Metrics/ClassLength, Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
class AnalyticsEngine
  include InternalVitalsFilter

  CACHE_TTL = 5.minutes

  def self.pageviews(site, period:, axis:)
    cache_key = "pageviews_#{site.id}_#{period}_#{axis}"

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      new(site, period: period, axis: axis).calculate_pageviews
    end
  end

  def self.heatmap(site, url:, viewport:)
    # Events store the raw window.location.href, so the same page arrives under
    # many spellings (query strings, fragments, trailing slash). Normalize once
    # here so the cache key and the aggregation both key on the canonical page.
    normalized_url = normalize_page_url(url)
    cache_key = "heatmap_#{site.id}_#{normalized_url}_#{viewport}"

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      new(site, period: nil, axis: nil).calculate_heatmap(url: normalized_url, viewport: viewport)
    end
  end

  def self.performance(site, period:, percentile:)
    cache_key = "performance_#{site.id}_#{period}_#{percentile}"

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      new(site, period: period, axis: nil).calculate_performance(percentile: percentile)
    end
  end

  def self.funnel(site, funnel, period:)
    cache_key = "funnel_#{site.id}_#{funnel.id}_#{period}"

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      new(site, period: period, axis: nil).calculate_funnel(funnel)
    end
  end

  def self.retention(site, cohort_unit:)
    cache_key = "retention_#{site.id}_#{cohort_unit}"

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      new(site, period: nil, axis: nil).calculate_retention(cohort_unit: cohort_unit)
    end
  end

  def self.mobile_user_agent?(user_agent)
    return false if user_agent.blank?

    user_agent.match?(/Mobi|Android|iPhone|iPad|Windows Phone/i)
  end

  # Canonical page identity for heatmap grouping: scheme+host+path with the
  # query string, fragment and trailing slash removed. Clicks on the same page
  # reached via different query params must land in the same grid.
  def self.normalize_page_url(raw)
    # Guard against non-String params (e.g. ?url[]=… gives an Array): the
    # controller already rejects these with 422, but never let a non-String
    # reach URI.parse / delete_suffix and turn into a 500 for other callers.
    return '' unless raw.is_a?(String) && raw.present?

    uri = URI.parse(raw)
    path = uri.path.presence || '/'
    path = path == '/' ? '/' : path.delete_suffix('/')

    if uri.scheme.present? && uri.host.present?
      origin = "#{uri.scheme}://#{uri.host}"
      origin += ":#{uri.port}" if uri.port && uri.port != uri.default_port
      "#{origin}#{path}"
    else
      path
    end
  rescue URI::InvalidURIError
    raw
  end

  def self.normalize_path(url_or_path)
    return '' unless url_or_path.is_a?(String) && url_or_path.present?

    uri = URI.parse(url_or_path)
    path = uri.path.presence || '/'
    path == '/' ? '/' : path.delete_suffix('/')
  rescue URI::InvalidURIError
    cleaned = url_or_path.split('?').first.split('#').first
    cleaned = '/' if cleaned.blank?
    cleaned = cleaned.delete_suffix('/') if cleaned != '/'
    cleaned
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
                            'events.occurred_at, events.properties, sessions.fingerprint'
                          ).to_a
    current_events = reject_internal_vitals(current_events)

    # Fetch events for previous period (excluding bots; see note above on session flag)
    previous_events = @site.events
                           .joins(:session)
                           .where(events: { is_bot: false })
                           .where(sessions: { is_bot: false })
                           .where(occurred_at: previous_start...previous_end)
                           .select('events.id, events.event_type, events.session_id, ' \
                                   'events.properties, sessions.fingerprint')
                           .to_a
    previous_events = reject_internal_vitals(previous_events)

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
    # page_url is stored raw (query string / fragment / trailing slash included),
    # so it cannot be matched exactly in SQL. Bound the scan to just this page's
    # spellings so sibling/child pages (e.g. /products vs /products/sub, or root
    # vs /about) are never materialized. The Ruby normalization below is the
    # source of truth; the SQL predicate only limits how many rows we load.
    clicks = same_page_clicks(url)
             .select('events.x_ratio, events.y_ratio, events.user_agent, events.page_url')
             .to_a

    filtered_clicks = clicks.select do |c|
      next false unless self.class.normalize_page_url(c.page_url) == url

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

  def calculate_performance(percentile:)
    now = Time.current
    current_start, current_end, = calculate_ranges(now, @period)

    vitals = @site.web_vitals
                  .joins(:session)
                  .where(sessions: { is_bot: false })
                  .where(web_vitals: { created_at: current_start..current_end })
                  .to_a

    lcp_values = vitals.map(&:lcp_ms).compact
    fid_values = vitals.map(&:fid_ms).compact
    cls_values = vitals.map(&:cls_score).compact.map(&:to_f)
    ttfb_values = vitals.map(&:ttfb_ms).compact
    fcp_values = vitals.map(&:fcp_ms).compact

    lcp_pct = calculate_percentile(lcp_values, percentile)
    fid_pct = calculate_percentile(fid_values, percentile)
    cls_pct = calculate_percentile(cls_values, percentile)
    ttfb_pct = calculate_percentile(ttfb_values, percentile)
    fcp_pct = calculate_percentile(fcp_values, percentile)

    # Classify from the raw percentile, not the rounded display value: a value
    # just over a threshold (e.g. LCP 2500.25) would otherwise round down to the
    # boundary (2500) and be misrated as good instead of needs_improvement.
    {
      lcp: { value: lcp_pct&.round, rating: classify_lcp(lcp_pct) },
      fid: { value: fid_pct&.round, rating: classify_fid(fid_pct) },
      cls: { value: cls_pct&.round(4), rating: classify_cls(cls_pct) },
      ttfb: { value: ttfb_pct&.round, rating: classify_ttfb(ttfb_pct) },
      fcp: { value: fcp_pct&.round, rating: classify_fcp(fcp_pct) }
    }
  end

  def calculate_funnel(funnel)
    now = Time.current
    current_start, current_end = calculate_ranges(now, @period)

    steps = normalize_funnel_steps(funnel.steps)

    # Fetch every non-bot event in the window regardless of type: a funnel may
    # mix URL steps (matched on page_url of pageview events) and event steps
    # (matched on event_type), so restricting to pageviews here would make event
    # steps unreachable. Internal Web Vitals pings are dropped so a "custom"
    # event step is not silently satisfied by a tracking ping.
    events = @site.events
                  .joins(:session)
                  .where(events: { is_bot: false })
                  .where(sessions: { is_bot: false })
                  .where(occurred_at: current_start..current_end)
                  .select('events.session_id, events.event_type, events.page_url, ' \
                          'events.occurred_at, events.properties')
                  .order('events.occurred_at ASC')
                  .to_a
    events = reject_internal_vitals(events)

    events_by_session = events.group_by(&:session_id)
    step_counts = Array.new(steps.size, 0)

    events_by_session.each_value do |session_events|
      current_step_idx = 0
      last_event_time = nil

      session_events.each do |event|
        break if current_step_idx >= steps.size

        next unless step_matches?(steps[current_step_idx], event)
        next unless last_event_time.nil? || event.occurred_at >= last_event_time

        current_step_idx += 1
        last_event_time = event.occurred_at
      end

      current_step_idx.times do |i|
        step_counts[i] += 1
      end
    end

    steps_data = steps.map.with_index do |step, idx|
      count = step_counts[idx]
      next_count = step_counts[idx + 1] || 0

      if idx < steps.size - 1
        drop_off = count - next_count
        drop_off_rate = count.positive? ? (drop_off.to_f / count * 100.0).round(2) : 0.0
      else
        drop_off = 0
        drop_off_rate = 0.0
      end

      {
        step_number: idx + 1,
        type: step['type'],
        value: step['value'],
        count: count,
        drop_off: drop_off,
        drop_off_rate: drop_off_rate
      }
    end

    first_step_count = step_counts[0] || 0
    last_step_count = step_counts.last || 0
    completion_rate = first_step_count.positive? ? (last_step_count.to_f / first_step_count * 100.0).round(2) : 0.0

    {
      id: funnel.id,
      name: funnel.name,
      completion_rate: completion_rate,
      steps: steps_data
    }
  end

  def calculate_retention(cohort_unit:)
    # Fetch all non-bot sessions for the site to determine cohorts and activity.
    sessions = @site.sessions.where(is_bot: false)
                    .select(:id, :fingerprint, :started_at, :created_at)
                    .to_a

    # Drop sessions whose only event is the tracking snippet's internal Web Vitals
    # ping. When a page is held open past the session cutoff, that unload ping can
    # open a fresh non-bot session with no real interaction; counting it as a
    # revisit inflates retention for cohorts that cross a period boundary. PV and
    # funnel aggregation already discard these pings via reject_internal_vitals;
    # here we discard the whole session when it carries nothing else. Sessions with
    # no events at all are left untouched (they never held a vitals ping).
    sessions = reject_vitals_only_sessions(sessions)

    # Group sessions by fingerprint (the unique identifier for a user)
    sessions_by_fingerprint = sessions.group_by(&:fingerprint)

    user_cohorts = {}
    user_active_periods = {}

    sessions_by_fingerprint.each do |fingerprint, user_sessions|
      period_starts = user_sessions.map do |s|
        t = (s.started_at || s.created_at).in_time_zone
        cohort_unit == 'week' ? t.beginning_of_week.to_date : t.beginning_of_month.to_date
      end.uniq

      user_cohorts[fingerprint] = period_starts.min
      user_active_periods[fingerprint] = period_starts
    end

    # Determine the target cohort start dates (12 intervals ending with the current one).
    now = Time.current.in_time_zone
    current_start = cohort_unit == 'week' ? now.beginning_of_week.to_date : now.beginning_of_month.to_date

    cohort_dates = (0..11).map do |i|
      cohort_unit == 'week' ? current_start - i.weeks : current_start - i.months
    end.reverse

    # Build the matrix
    matrix = cohort_dates.map do |cohort_date|
      cohort_users_fp = user_cohorts.select { |_, start_date| start_date == cohort_date }.keys
      cohort_size = cohort_users_fp.size

      activity = (0..11).map do |p|
        target_date = cohort_unit == 'week' ? cohort_date + p.weeks : cohort_date + p.months
        if target_date > current_start
          nil
        elsif cohort_size.positive?
          revisited_count = cohort_users_fp.count { |fp| user_active_periods[fp].include?(target_date) }
          ((revisited_count.to_f / cohort_size) * 100.0).round(2)
        else
          0.0
        end
      end

      cohort_label = cohort_unit == 'week' ? cohort_date.strftime('%Y-%m-%d') : cohort_date.strftime('%Y-%m')

      {
        cohort: cohort_label,
        cohort_size: cohort_size,
        activity: activity
      }
    end

    {
      cohort_unit: cohort_unit,
      matrix: matrix
    }
  end

  private

  # Coerce funnel steps into the canonical {"type", "value"} hash. Rows persisted
  # by the current model are already canonical; legacy string rows (or hashes
  # with symbol keys) are tolerated so historical funnels keep analyzing.
  def normalize_funnel_steps(raw_steps)
    Array(raw_steps).map do |step|
      if step.is_a?(Hash)
        { 'type' => step['type'] || step[:type] || 'url', 'value' => step['value'] || step[:value] }
      else
        { 'type' => 'url', 'value' => step }
      end
    end
  end

  # A URL step is reached by a pageview whose normalized path equals the step's
  # normalized value; an event step is reached by any event whose event_type
  # equals the step's value. Funnel validation constrains event values to the
  # collectable event types (EventCollector::ALLOWED_EVENT_TYPES), so this
  # comparison can always be satisfied by data from /events/collect.
  def step_matches?(step, event)
    if step['type'] == 'event'
      event.event_type == step['value']
    else
      event.event_type == 'pageview' &&
        self.class.normalize_path(event.page_url) == self.class.normalize_path(step['value'])
    end
  end

  # Non-bot click events whose raw page_url normalizes to `url`, bounded in SQL
  # to this page's exact spellings only. `url` is already normalized
  # (scheme+host+path, no trailing slash except the site root "…/").
  #
  # Every raw value that normalizes back to `url` is one of two stems — the bare
  # form and the trailing-slash form — optionally followed by "?query" or
  # "#fragment". For the site root the bare stem is the origin-only href
  # ("https://host") that carries no path slash, so it is covered too. Matching
  # these stems exactly (plus the ?/# LIKE variants) keeps a root or parent-path
  # heatmap from materializing sibling/child pages the way an "url%" prefix would.
  def same_page_clicks(url)
    base = @site.events
                .joins(:session)
                .where(events: { event_type: 'click', is_bot: false })
                .where(sessions: { is_bot: false })

    # Include the explicit default-port spelling (…:443/… , …:80/…) too: it
    # normalizes to the same portless key, but a raw href that kept the port
    # would otherwise be filtered out in SQL before the Ruby check sees it.
    canonical_forms = [url, default_port_variant(url)].compact.uniq
    stems = canonical_forms.flat_map do |form|
      no_slash = form.delete_suffix('/')
      [no_slash, "#{no_slash}/"]
    end.uniq

    conditions = []
    binds = []
    stems.each do |stem|
      escaped = ActiveRecord::Base.sanitize_sql_like(stem)
      conditions << 'events.page_url = ?'
      conditions << "events.page_url LIKE ? ESCAPE '\\'"
      conditions << "events.page_url LIKE ? ESCAPE '\\'"
      binds << stem << "#{escaped}?%" << "#{escaped}#%"
    end

    base.where(conditions.join(' OR '), *binds)
  end

  # The same canonical page written with its scheme's default port made explicit
  # (https://host → https://host:443), or nil when `url` has no scheme/host.
  def default_port_variant(url)
    uri = URI.parse(url)
    return nil unless uri.scheme.present? && uri.host.present? && uri.default_port

    path = uri.path.presence || '/'
    path = path == '/' ? '/' : path.delete_suffix('/')
    "#{uri.scheme}://#{uri.host}:#{uri.default_port}#{path}"
  rescue URI::InvalidURIError
    nil
  end

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

  def calculate_percentile(values, percentile_str)
    return nil if values.empty?

    sorted = values.sort

    p = case percentile_str
        when 'p50' then 0.50
        when 'p75' then 0.75
        when 'p95' then 0.95
        else raise ArgumentError, "Invalid percentile: #{percentile_str}"
        end

    n = sorted.size
    return sorted[0].to_f if n == 1

    i = p * (n - 1)
    k = i.floor
    d = i - k

    if k >= n - 1
      sorted[n - 1].to_f
    else
      (sorted[k] + (d * (sorted[k + 1] - sorted[k]))).to_f
    end
  end

  def classify_lcp(val)
    return nil if val.nil?

    if val <= 2500
      'good'
    elsif val <= 4000
      'needs_improvement'
    else
      'poor'
    end
  end

  def classify_fid(val)
    return nil if val.nil?

    if val <= 100
      'good'
    elsif val <= 300
      'needs_improvement'
    else
      'poor'
    end
  end

  def classify_cls(val)
    return nil if val.nil?

    if val <= 0.1
      'good'
    elsif val <= 0.25
      'needs_improvement'
    else
      'poor'
    end
  end

  def classify_ttfb(val)
    return nil if val.nil?

    if val <= 800
      'good'
    elsif val <= 1800
      'needs_improvement'
    else
      'poor'
    end
  end

  def classify_fcp(val)
    return nil if val.nil?

    if val <= 1800
      'good'
    elsif val <= 3000
      'needs_improvement'
    else
      'poor'
    end
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
