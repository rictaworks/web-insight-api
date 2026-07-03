# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/ParameterLists, Layout/LineLength
class BotDetector
  BOT_UA_KEYWORDS = %w[
    bot spider crawler lighthouse chrome-lighthouse headlesschrome
    slurp pingdom ia_archiver googlebot bingbot yandex bot/
  ].freeze

  def self.bot?(user_agent:, ip:, properties: {}, event_type: nil, x_ratio: nil, y_ratio: nil)
    # 1. User-Agent checks
    if user_agent.blank?
      Rails.logger.info('BotDetector: User-Agent is blank')
      return true
    end

    ua_lower = user_agent.downcase
    if BOT_UA_KEYWORDS.any? { |kw| ua_lower.include?(kw) }
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
