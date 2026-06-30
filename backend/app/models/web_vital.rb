class WebVital < ApplicationRecord
  belongs_to :site
  belongs_to :session

  validates :page_url, presence: true
end
