class Site < ApplicationRecord
  belongs_to :user
  has_many :sessions, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :web_vitals, dependent: :destroy
  has_many :funnels, dependent: :destroy
  has_many :alert_rules, dependent: :destroy
  has_many :ai_recommendations, dependent: :destroy
  has_many :daily_ai_usages, class_name: 'DailyAiUsage', dependent: :destroy

  before_validation :generate_api_key, on: :create

  validates :name, presence: true
  validates :url, presence: true
  validates :api_key, presence: true, uniqueness: true

  private

  def generate_api_key
    self.api_key ||= SecureRandom.hex(32)
  end
end
