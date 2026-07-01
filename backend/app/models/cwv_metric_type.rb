class CwvMetricType < ApplicationRecord
  validates :name, presence: true, uniqueness: true
end
