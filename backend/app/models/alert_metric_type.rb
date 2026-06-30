class AlertMetricType < ApplicationRecord
  validates :name, presence: true, uniqueness: true
end
