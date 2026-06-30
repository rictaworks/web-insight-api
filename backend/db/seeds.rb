# Seed master data idempotently

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
