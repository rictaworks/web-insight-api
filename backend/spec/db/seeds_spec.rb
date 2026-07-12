require 'rails_helper'

RSpec.describe 'db/seeds.rb' do
  def run_seeds
    load Rails.root.join('db/seeds.rb')
  end

  it 'seeds the default bot rules when the table is empty' do
    BotRule.delete_all

    run_seeds

    expect(BotRule.pluck(:pattern)).to include('bot', 'googlebot', 'bingbot')
  end

  it 'does not recreate a default pattern an admin removed, on rerun' do
    # Regression test: bot_rules is mutable admin configuration (see
    # Admin::BotRulesController and RailsAdmin), unlike the other master
    # data seeded above it. Rerunning db:seed after an admin removes a
    # default pattern must not silently restore it.
    BotRule.delete_all
    run_seeds
    BotRule.find_by!(pattern: 'bot').destroy!

    run_seeds

    expect(BotRule.pluck(:pattern)).not_to include('bot')
  end
end
