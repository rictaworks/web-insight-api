require 'rails_helper'

RSpec.describe Site, type: :model do
  let(:user) { User.create!(google_sub: 'sub_test', display_name: 'Test') }

  describe 'callbacks' do
    it 'automatically generates a 64-character api_key on creation if not present' do
      site = Site.new(name: 'Test Site', url: 'https://example.com', user: user)
      expect(site.api_key).to be_nil
      expect(site.valid?).to be true
      expect(site.api_key).to be_present
      expect(site.api_key.length).to eq(64)
    end

    it 'does not overwrite an explicitly provided api_key' do
      explicit_key = 'a' * 64
      site = Site.new(name: 'Test Site', url: 'https://example.com', user: user, api_key: explicit_key)
      expect(site.valid?).to be true
      expect(site.api_key).to eq(explicit_key)
    end
  end
end
