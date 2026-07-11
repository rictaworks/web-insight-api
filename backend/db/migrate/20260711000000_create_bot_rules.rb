class CreateBotRules < ActiveRecord::Migration[7.1]
  # Mirrors BotDetector::DEFAULT_BOT_UA_KEYWORDS as of when this migration was
  # written. Duplicated here rather than referenced from the app, because
  # migrations must keep working unchanged even after application code (and
  # its constants) evolve later.
  DEFAULT_BOT_UA_KEYWORDS = %w[
    bot spider crawler lighthouse chrome-lighthouse headlesschrome
    slurp pingdom ia_archiver googlebot bingbot yandex bot/
  ].freeze

  def up
    create_table :bot_rules, id: :string do |t|
      t.string :pattern, null: false

      t.timestamps
    end
    add_index :bot_rules, :pattern, unique: true

    seed_default_bot_rules
  end

  def down
    drop_table :bot_rules
  end

  private

  # db/seeds.rb is not re-run when this migration deploys onto an existing
  # production database (only db:migrate runs), and BotDetector falls back to
  # the defaults only while bot_rules is empty (see app/services/bot_detector.rb).
  # Without seeding here, an existing production DB would keep bot_rules empty
  # until someone remembers to run db:seed, and the built-in patterns would
  # silently disappear the moment an admin added their first custom rule
  # through RailsAdmin.
  def seed_default_bot_rules
    bot_rule = Class.new(ActiveRecord::Base) { self.table_name = 'bot_rules' }
    now = Time.current
    rows = DEFAULT_BOT_UA_KEYWORDS.map do |pattern|
      { id: SecureRandom.uuid, pattern: pattern, created_at: now, updated_at: now }
    end
    bot_rule.insert_all(rows)
  end
end
