class Event < ApplicationRecord
  belongs_to :site
  belongs_to :session

  validates :event_type, presence: true
end
