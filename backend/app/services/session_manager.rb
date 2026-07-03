# rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
class SessionManager
  # Find or create a session for the event.
  # Returns the Session object.
  def self.find_or_create_session(site_id:, fingerprint:, referrer:, page_url:, is_bot:, payload: {})
    now = Time.current
    cutoff = 30.minutes.ago

    # Look for an active session (last_seen_at within 30 minutes, same day in JST)
    active_session = Session.where(site_id: site_id, fingerprint: fingerprint)
                            .where(last_seen_at: cutoff..)
                            .order(last_seen_at: :desc)
                            .find do |s|
                              # started_at is nullable (e.g. manually created rows), so fall back to
                              # created_at rather than calling in_time_zone on nil.
                              started = (s.started_at || s.created_at).in_time_zone('Asia/Tokyo')
                              started.to_date == now.in_time_zone('Asia/Tokyo').to_date
                            end

    if active_session
      # Propagate bot flag if the new request is marked as bot
      active_session.update!(
        last_seen_at: now,
        is_bot: active_session.is_bot || is_bot
      )
      active_session
    else
      # Extract UTM parameters from payload or page_url. A blank payload
      # value (e.g. "") must fall back to the URL just like a missing one.
      utm_source = payload['utm_source'].presence || parse_query_param(page_url, 'utm_source')
      utm_medium = payload['utm_medium'].presence || parse_query_param(page_url, 'utm_medium')
      utm_campaign = payload['utm_campaign'].presence || parse_query_param(page_url, 'utm_campaign')

      channel = determine_channel(
        utm_source: utm_source,
        utm_medium: utm_medium,
        referrer: referrer
      )

      Session.create!(
        site_id: site_id,
        fingerprint: fingerprint,
        utm_source: utm_source.presence,
        utm_medium: utm_medium.presence,
        utm_campaign: utm_campaign.presence,
        channel: channel,
        is_bot: is_bot,
        started_at: now,
        last_seen_at: now
      )
    end
  end

  def self.parse_query_param(url, param)
    return nil if url.blank?

    uri = URI.parse(url)
    return nil unless uri.query

    value = CGI.parse(uri.query)[param]&.first
    # A malformed percent-encoded sequence (e.g. "%E0%A4%A") decodes to a
    # string with invalid byte sequences; treat it as absent rather than
    # letting a later String#downcase raise ArgumentError.
    return nil unless value.nil? || value.valid_encoding?

    value
  rescue URI::InvalidURIError
    nil
  end

  def self.determine_channel(utm_source:, utm_medium:, referrer:)
    medium = utm_medium.to_s.downcase
    source = utm_source.to_s.downcase
    ref = referrer.to_s.downcase

    # 1. Paid
    return 'paid' if %w[cpc ppc cpm ad advertising].include?(medium) || source.include?('ad')

    # 2. Email
    return 'email' if medium == 'email' || source == 'email'

    # 3. Social
    social_domains = %w[twitter.com t.co facebook.com fb.me instagram.com linkedin.com youtube.com line.me tiktok.com]
    return 'social' if medium == 'social' || social_domains.any? { |d| ref.include?(d) }

    # 4. Display
    return 'display' if medium == 'display'

    # 5. Organic Search
    search_domains = %w[google. yahoo. bing. baidu. duckduckgo.]
    return 'organic' if search_domains.any? { |d| ref.include?(d) }

    # 6. Direct
    return 'direct' if referrer.blank?

    # 7. Referral
    return 'referral' if referrer.present?

    'other'
  end

  private_class_method :parse_query_param, :determine_channel
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
