class AlertRule < ApplicationRecord
  belongs_to :site
  has_many :alert_logs, dependent: :destroy

  validates :metric, presence: true
  validates :condition, presence: true
  validates :threshold, presence: true
end
