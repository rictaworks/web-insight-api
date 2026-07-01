class AgeGroup < ApplicationRecord
  validates :name, presence: true, uniqueness: true
end
