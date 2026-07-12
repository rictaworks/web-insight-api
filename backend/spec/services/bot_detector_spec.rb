require 'rails_helper'

RSpec.describe BotDetector do
  # Rails.cache is a process-wide memory store shared across spec files, so
  # a stale 'bot_ua_keywords' entry left behind here would otherwise leak
  # into unrelated specs (e.g. events_controller_spec's bot-detection test)
  # depending on run order.
  before { Rails.cache.clear }
  after { Rails.cache.clear }

  describe '.bot_ua_keywords' do
    it 'returns custom patterns from the bot_rules table when present' do
      BotRule.delete_all
      BotRule.create!(pattern: 'custom_crawler')

      expect(described_class.bot_ua_keywords).to contain_exactly('custom_crawler')
    end

    it 'falls back to the default keywords when the bot_rules table is empty' do
      # Admin::BotRulesController#update rejects any update that would leave
      # zero rules, so an empty table only happens before the initial
      # db/seeds.rb run (fresh migration, or a test DB that skips seeding) —
      # not from an admin intentionally disabling keyword matching.
      BotRule.delete_all

      expect(described_class.bot_ua_keywords).to eq(BotDetector::DEFAULT_BOT_UA_KEYWORDS)
    end

    it 'falls back to the default keywords when the bot_rules table does not exist' do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).with('bot_rules').and_return(false)

      expect(described_class.bot_ua_keywords).to eq(BotDetector::DEFAULT_BOT_UA_KEYWORDS)
    end
  end

  describe '.bot?' do
    it 'matches a stored pattern case-insensitively against the User-Agent' do
      # Regression test: an admin-entered pattern like "Googlebot" must still
      # match a lowercase User-Agent string; the comparison must not depend on
      # the admin having typed the pattern in lowercase.
      BotRule.delete_all
      BotRule.create!(pattern: 'Googlebot')

      expect(
        described_class.bot?(user_agent: 'Mozilla/5.0 (compatible; Googlebot/2.1)', ip: '1.2.3.4')
      ).to be true
    end
  end
end
