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
  # No `on: :create`: legacy rows created before verify_token was required may
  # hold NULL or an empty string. Running this on every save backfills a token
  # whenever the value is blank (existing tokens are left intact) so a later
  # update! — e.g. the verified: true write during event collection — cannot
  # fail validation.
  before_validation :generate_verify_token

  validates :name, presence: true
  validates :url, presence: true
  validates :api_key, presence: true, uniqueness: true
  validates :verify_token, presence: true

  def generate_snippet
    SnippetBuilder.new(self).build
  end

  private

  def generate_api_key
    self.api_key ||= SecureRandom.hex(32)
  end

  def generate_verify_token
    self.verify_token = SecureRandom.hex(32) if verify_token.blank?
  end
end
