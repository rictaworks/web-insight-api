require 'rails_helper'

RSpec.describe Funnel, type: :model do
  let(:user) { User.create!(google_sub: 'sub_test', display_name: 'Test') }
  let(:site) { Site.create!(name: 'Test Site', url: 'https://example.com', user: user) }

  describe 'validations' do
    it 'is valid with a name and a valid steps array' do
      funnel = Funnel.new(name: 'Conversion Funnel', site: site, steps: ['/', '/products', '/cart'])
      expect(funnel.valid?).to be true
    end

    it 'is invalid without a name' do
      funnel = Funnel.new(site: site, steps: ['/', '/products'])
      expect(funnel.valid?).to be false
      expect(funnel.errors[:name]).to include("can't be blank")
    end

    it 'is invalid without steps' do
      funnel = Funnel.new(name: 'Funnel', site: site, steps: nil)
      expect(funnel.valid?).to be false
      expect(funnel.errors[:steps]).to include("can't be blank")
    end

    it 'is invalid if steps is not an array' do
      funnel = Funnel.new(name: 'Funnel', site: site, steps: 'not-an-array')
      expect(funnel.valid?).to be false
      expect(funnel.errors[:steps]).to include('must be an array')
    end

    it 'is invalid if steps size is less than 2' do
      funnel = Funnel.new(name: 'Funnel', site: site, steps: ['/'])
      expect(funnel.valid?).to be false
      expect(funnel.errors[:steps]).to include('must contain between 2 and 20 steps')
    end

    it 'is invalid if steps size is greater than 20' do
      funnel = Funnel.new(name: 'Funnel', site: site, steps: (1..21).map { |i| "/step-#{i}" })
      expect(funnel.valid?).to be false
      expect(funnel.errors[:steps]).to include('must contain between 2 and 20 steps')
    end

    it 'is invalid if any step is not a non-empty value' do
      funnel = Funnel.new(name: 'Funnel', site: site, steps: ['/', '', '/cart'])
      expect(funnel.valid?).to be false
      expect(funnel.errors[:steps]).to include('step 2 must be a url or event with a non-empty value')

      funnel2 = Funnel.new(name: 'Funnel', site: site, steps: ['/', nil, '/cart'])
      expect(funnel2.valid?).to be false
      expect(funnel2.errors[:steps]).to include('step 2 must be a url or event with a non-empty value')
    end

    it 'normalizes bare string steps into canonical {type, value} url steps' do
      funnel = Funnel.new(name: 'Funnel', site: site, steps: ['/', '/checkout'])
      expect(funnel.valid?).to be true
      expect(funnel.steps).to eq(
        [
          { 'type' => 'url', 'value' => '/' },
          { 'type' => 'url', 'value' => '/checkout' }
        ]
      )
    end

    it 'accepts the documented object-shaped url and event steps' do
      funnel = Funnel.new(
        name: 'Engagement Funnel',
        site: site,
        steps: [{ type: 'url', value: '/' }, { type: 'event', value: 'click' }]
      )
      expect(funnel.valid?).to be true
      expect(funnel.steps).to eq(
        [
          { 'type' => 'url', 'value' => '/' },
          { 'type' => 'event', 'value' => 'click' }
        ]
      )
    end

    it 'is invalid if a step type is not url or event' do
      funnel = Funnel.new(
        name: 'Funnel',
        site: site,
        steps: [{ type: 'foo', value: '/' }, { type: 'url', value: '/cart' }]
      )
      expect(funnel.valid?).to be false
      expect(funnel.errors[:steps]).to include('step 1 must be a url or event with a non-empty value')
    end

    it 'is invalid if an event step value is not a collectable event type' do
      funnel = Funnel.new(
        name: 'Funnel',
        site: site,
        steps: [{ type: 'url', value: '/' }, { type: 'event', value: 'signup' }]
      )
      expect(funnel.valid?).to be false
      expect(funnel.errors[:steps]).to include(
        'step 2 event value must be one of: pageview, click, scroll, custom'
      )
    end

    it 'is idempotent when re-validating already-canonical steps' do
      funnel = Funnel.create!(
        name: 'Funnel',
        site: site,
        steps: [{ type: 'url', value: '/' }, { type: 'event', value: 'click' }]
      )
      funnel.valid?
      expect(funnel.steps).to eq(
        [
          { 'type' => 'url', 'value' => '/' },
          { 'type' => 'event', 'value' => 'click' }
        ]
      )
    end
  end
end
