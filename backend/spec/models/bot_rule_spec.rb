require 'rails_helper'

RSpec.describe BotRule, type: :model do
  # db:seed populates default bot rules on a fresh database (see db/seeds.rb),
  # and CI's db:prepare runs it before the suite starts — so these examples
  # cannot assume the table starts empty without clearing it themselves.
  before do
    BotRule.delete_all
    Rails.cache.clear
  end
  after { Rails.cache.clear }

  it 'invalidates the bot_ua_keywords cache on create' do
    # Regression test: RailsAdmin's generic new/edit/delete UI mutates BotRule
    # directly, bypassing Admin::BotRulesController entirely, so cache
    # invalidation must live on the model (after_commit) rather than only in
    # that controller — otherwise BotDetector keeps serving stale patterns
    # for up to an hour after an edit made through RailsAdmin.
    expect(BotDetector.bot_ua_keywords).to eq(BotDetector::DEFAULT_BOT_UA_KEYWORDS)

    described_class.create!(pattern: 'new_admin_added_bot')

    expect(BotDetector.bot_ua_keywords).to include('new_admin_added_bot')
  end

  it 'invalidates the bot_ua_keywords cache on update' do
    rule = described_class.create!(pattern: 'old_pattern')
    BotDetector.bot_ua_keywords # prime the cache

    rule.update!(pattern: 'renamed_pattern')

    expect(BotDetector.bot_ua_keywords).to include('renamed_pattern')
    expect(BotDetector.bot_ua_keywords).not_to include('old_pattern')
  end

  it 'invalidates the bot_ua_keywords cache on destroy' do
    described_class.create!(pattern: 'keeper_bot')
    rule = described_class.create!(pattern: 'temporary_bot')
    BotDetector.bot_ua_keywords # prime the cache with the row present

    rule.destroy!

    expect(BotDetector.bot_ua_keywords).not_to include('temporary_bot')
  end

  describe 'deleting the last remaining rule' do
    it 'is prevented, so BotDetector never silently falls back to the defaults' do
      # Regression test: RailsAdmin's delete/bulk_delete actions destroy rows
      # directly, bypassing Admin::BotRulesController's "at least one
      # keyword" guard. Without this model-level invariant, deleting the
      # last row here would make BotDetector.bot_ua_keywords fall back to
      # DEFAULT_BOT_UA_KEYWORDS, silently re-enabling the built-in filters
      # instead of honoring (or blocking) the admin's intended change.
      rule = described_class.create!(pattern: 'only_bot')

      expect { rule.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(described_class.count).to eq(1)
      expect(BotDetector.bot_ua_keywords).to eq(['only_bot'])
    end

    it 'is allowed once more than one rule exists' do
      first = described_class.create!(pattern: 'first_bot')
      described_class.create!(pattern: 'second_bot')

      expect { first.destroy! }.not_to raise_error
      expect(described_class.count).to eq(1)
    end
  end
end
