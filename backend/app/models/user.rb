class User < ApplicationRecord
  has_many :sites, dependent: :destroy

  validates :google_sub, presence: true, uniqueness: true
  validates :display_name, presence: true
end
