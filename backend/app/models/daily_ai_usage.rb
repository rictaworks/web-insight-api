class DailyAiUsage < ApplicationRecord
  self.table_name = 'daily_ai_usage'

  belongs_to :site

  validates :usage_date, presence: true
  validates :used_count, presence: true
end
