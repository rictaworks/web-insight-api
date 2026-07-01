class Session < ApplicationRecord
  belongs_to :site
  has_many :events, dependent: :destroy
  has_many :web_vitals, dependent: :destroy

  validates :fingerprint, presence: true
end
