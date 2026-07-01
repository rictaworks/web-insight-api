class Site < ApplicationRecord
  belongs_to :user
  has_many :sessions, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :web_vitals, dependent: :destroy
  has_many :funnels, dependent: :destroy
  has_many :alert_rules, dependent: :destroy
  has_many :ai_recommendations, dependent: :destroy
  has_many :daily_ai_usages, class_name: 'DailyAiUsage', dependent: :destroy

  validates :name, presence: true
  validates :url, presence: true
  validates :api_key, presence: true, uniqueness: true
end
