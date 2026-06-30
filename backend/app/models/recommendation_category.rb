class RecommendationCategory < ApplicationRecord
  validates :name, presence: true, uniqueness: true
end
