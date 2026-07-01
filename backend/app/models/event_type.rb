class EventType < ApplicationRecord
  validates :name, presence: true, uniqueness: true
end
