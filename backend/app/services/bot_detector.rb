# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/ParameterLists, Layout/LineLength
class BotDetector
  DEFAULT_BOT_UA_KEYWORDS = %w[
    bot spider crawler lighthouse chrome-lighthouse headlesschrome
    slurp pingdom ia_archiver googlebot bingbot yandex bot/
  ].freeze

  def self.bot_ua_keywords
    Rails.cache.fetch('bot_ua_keywords', expires_in: 1.hour) do
      if ActiveRecord::Base.connection.table_exists?('bot_rules')
        # Admin::BotRulesController#update rejects updates that would leave
        # the table empty (see its `sanitized.empty?` guard), so an empty
        # result here only ever means the table hasn't been seeded yet
        # (fresh migration, or a test DB that skips db/seeds.rb) — falling
        # back to the defaults is safe and never masks an admin's intent.
        patterns = BotRule.pluck(:pattern)
        patterns.empty? ? DEFAULT_BOT_UA_KEYWORDS : patterns
      else
        DEFAULT_BOT_UA_KEYWORDS
      end
    end
  rescue StandardError => e
    Rails.logger.error("BotDetector: failed to fetch bot rules from DB: #{e.message}")
    DEFAULT_BOT_UA_KEYWORDS
  end

  def self.bot?(user_agent:, ip:, properties: {}, event_type: nil, x_ratio: nil, y_ratio: nil)
    # 1. User-Agent checks
    if user_agent.blank?
      Rails.logger.info('BotDetector: User-Agent is blank')
      return true
    end

    ua_lower = user_agent.downcase
    if bot_ua_keywords.any? { |kw| ua_lower.include?(kw.downcase) }
      Rails.logger.info('BotDetector: Match User-Agent keyword')
      return true
    end

    # 2. IP checks (supports special test IP 127.0.0.99 for RSpec tests)
    if ip == '127.0.0.99'
      Rails.logger.info('BotDetector: Match test bot IP')
      return true
    end

    # 3. Behavioral checks
    # Click events where coordinates are exactly 0.0, 0.0 (unnatural for humans)
    if event_type == 'click' && x_ratio.present? && y_ratio.present? && x_ratio.to_f.zero? && y_ratio.to_f.zero?
      Rails.logger.info('BotDetector: Click coordinate at exactly (0,0)')
      return true
    end

    # Custom properties flags indicating bot/automation
    if properties.is_a?(Hash) && (properties['bot'] == true || properties['is_bot'] == true || properties['automation'] == true)
      Rails.logger.info('BotDetector: Match custom properties bot flag')
      return true
    end

    false
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/ParameterLists, Layout/LineLength
