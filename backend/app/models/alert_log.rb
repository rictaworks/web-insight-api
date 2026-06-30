class AlertLog < ApplicationRecord
  belongs_to :alert_rule

  validates :fired_at, presence: true
  validates :metric_value, presence: true
end
