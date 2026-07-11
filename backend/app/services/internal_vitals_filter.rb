# Shared logic for excluding the tracking snippet's internal Web Vitals ping
# from traffic aggregation. The ping is ingested as an ordinary custom event
# so it can populate WebVital rows, but counting it as PV/UV/session/bounce
# traffic inflates metrics whenever a page is held open past the session
# cutoff and the unload ping opens a fresh session. Included by every service
# that aggregates events or sessions (AnalyticsEngine, AlertRuleEvaluator) so
# the exclusion rule stays identical everywhere it is applied.
module InternalVitalsFilter
  # Cap on how many session ids go into a single `WHERE session_id IN (...)`.
  # Kept well under SQLite's default bind-variable limit (999) so the lookup
  # never fails as a site's session history grows. PostgreSQL's limit is far
  # higher, so this batch size is comfortably safe on both.
  VITALS_LOOKUP_BATCH_SIZE = 500

  def reject_internal_vitals(events)
    marker = EventCollector::INTERNAL_VITALS_PROPERTY
    events.reject do |event|
      event.properties.is_a?(Hash) && event.properties[marker]
    end
  end

  # Session ids whose events are ALL the internal Web Vitals ping. A session
  # appears here only when it has at least one event and none of them is a
  # real interaction, so zero-event sessions are never flagged.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
  def vitals_only_session_ids(session_ids)
    return Set.new if session_ids.empty?

    marker = EventCollector::INTERNAL_VITALS_PROPERTY

    # Look the ids up in batches. The caller can pass every historical session
    # id, and a single `WHERE session_id IN (...)` would exceed the
    # database's bind variable limit once a site accumulates enough sessions,
    # failing the whole request. Slicing keeps each query bounded regardless
    # of history size.
    session_ids.each_slice(VITALS_LOOKUP_BATCH_SIZE).with_object(Set.new) do |batch, acc|
      events_by_session = Event.where(session_id: batch)
                               .select(:session_id, :properties)
                               .to_a
                               .group_by(&:session_id)

      events_by_session.each do |session_id, session_events|
        all_internal = session_events.all? do |event|
          event.properties.is_a?(Hash) && event.properties[marker]
        end
        acc << session_id if all_internal
      end
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength

  # Drops sessions whose only event(s) are the internal Web Vitals ping from
  # a session list, so session-based metrics (bounce rate, average duration,
  # retention) never treat a vitals-only session as real traffic.
  def reject_vitals_only_sessions(sessions)
    ids = vitals_only_session_ids(sessions.map(&:id))
    sessions.reject { |s| ids.include?(s.id) }
  end
end
