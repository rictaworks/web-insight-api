class ChannelType < ApplicationRecord
  validates :name, presence: true, uniqueness: true
end
