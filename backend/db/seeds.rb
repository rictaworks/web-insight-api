# Seed master data idempotently
# These lookup records are required in all environments (development / test / production).
# If adding environment-specific data in the future, wrap it in Rails.env.development? blocks.
raise "Unsupported Rails environment: #{Rails.env}" unless Rails.env.local? || Rails.env.production?

event_types = %w[pageview click scroll custom]
event_types.each do |name|
  EventType.find_or_create_by!(name: name)
end

channel_types = %w[organic paid referral social email direct display other]
channel_types.each do |name|
  ChannelType.find_or_create_by!(name: name)
end

alert_metric_types = %w[pv uv session bounce_rate avg_duration error_rate]
alert_metric_types.each do |name|
  AlertMetricType.find_or_create_by!(name: name)
end

cwv_metric_types = %w[LCP FID CLS TTFB FCP]
cwv_metric_types.each do |name|
  CwvMetricType.find_or_create_by!(name: name)
end

recommendation_categories = %w[UX SEO パフォーマンス コンテンツ]
recommendation_categories.each do |name|
  RecommendationCategory.find_or_create_by!(name: name)
end

age_groups = %w[10代 20代 30代 40代 50代 60代以上]
age_groups.each do |name|
  AgeGroup.find_or_create_by!(name: name)
end

Rails.logger.debug 'Master data seeded successfully.'

# Unlike the master data above, bot_rules is mutable configuration that
# admins edit via Admin::BotRulesController / RailsAdmin. Seeding must only
# populate the initial defaults when the table is empty, otherwise rerunning
# db:seed would silently recreate any default pattern an admin removed.
if BotRule.none?
  bot_rules = %w[
    bot spider crawler lighthouse chrome-lighthouse headlesschrome
    slurp pingdom ia_archiver googlebot bingbot yandex bot/
  ]
  bot_rules.each do |pattern|
    BotRule.find_or_create_by!(pattern: pattern)
  end
end
