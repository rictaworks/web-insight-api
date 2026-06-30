class AiRecommendation < ApplicationRecord
  belongs_to :site

  validates :category, presence: true
  validates :priority, presence: true
  validates :description, presence: true
end
