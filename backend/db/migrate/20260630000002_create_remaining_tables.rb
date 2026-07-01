class CreateRemainingTables < ActiveRecord::Migration[7.1]
  def change
    # 1. sites
    create_table :sites, id: :string do |t|
      t.references :user, type: :string, null: false, foreign_key: true
      t.string :name, null: false
      t.string :url, null: false
      t.string :api_key, null: false
      t.boolean :verified, default: false, null: false
      t.string :verify_token

      t.timestamps
    end
    add_index :sites, :api_key, unique: true

    # 2. sessions
    create_table :sessions, id: :string do |t|
      t.references :site, type: :string, null: false, foreign_key: true
      t.string :fingerprint, null: false
      t.string :channel
      t.string :utm_source
      t.string :utm_medium
      t.string :utm_campaign
      t.boolean :is_bot, default: false, null: false
      t.datetime :started_at
      t.datetime :last_seen_at
      t.datetime :created_at, null: false
    end
    # 3. events
    create_table :events, id: :string do |t|
      t.references :site, type: :string, null: false, foreign_key: true
      t.references :session, type: :string, null: false, foreign_key: true
      t.string :event_type, null: false
      t.string :page_url
      t.string :referrer
      t.string :user_agent
      if connection.adapter_name =~ /postg/i
        t.jsonb :properties
      else
        t.json :properties
      end
      t.decimal :x_ratio, precision: 5, scale: 4
      t.decimal :y_ratio, precision: 5, scale: 4
      t.boolean :is_bot, default: false, null: false
      t.datetime :occurred_at
      t.datetime :created_at, null: false
    end
    add_index :events, :occurred_at

    # 4. web_vitals
    create_table :web_vitals, id: :string do |t|
      t.references :site, type: :string, null: false, foreign_key: true
      t.references :session, type: :string, null: false, foreign_key: true
      t.string :page_url
      t.integer :lcp_ms
      t.integer :fid_ms
      t.decimal :cls_score, precision: 6, scale: 4
      t.integer :ttfb_ms
      t.integer :fcp_ms

      t.timestamps
    end

    # 5. funnels
    create_table :funnels, id: :string do |t|
      t.references :site, type: :string, null: false, foreign_key: true
      t.string :name, null: false
      if connection.adapter_name =~ /postg/i
        t.jsonb :steps
      else
        t.json :steps
      end

      t.timestamps
    end

    # 6. alert_rules
    create_table :alert_rules, id: :string do |t|
      t.references :site, type: :string, null: false, foreign_key: true
      t.string :metric
      t.string :condition
      t.decimal :threshold, precision: 12, scale: 4
      t.integer :cooldown_min, default: 60
      t.datetime :last_fired_at

      t.timestamps
    end

    # 7. alert_logs
    create_table :alert_logs, id: :string do |t|
      t.references :alert_rule, type: :string, null: false, foreign_key: true
      t.datetime :fired_at, null: false
      t.decimal :metric_value, precision: 12, scale: 4, null: false
      t.datetime :created_at, null: false
    end

    # 8. ai_recommendations
    create_table :ai_recommendations, id: :string do |t|
      t.references :site, type: :string, null: false, foreign_key: true
      t.string :category
      t.integer :priority
      t.text :description
      t.string :estimated_impact
      t.datetime :generated_at
      t.datetime :created_at, null: false
    end

    # 9. daily_ai_usage
    create_table :daily_ai_usage, id: :string do |t|
      t.references :site, type: :string, null: false, foreign_key: true
      t.date :usage_date, null: false
      t.integer :used_count, default: 0, null: false
      t.datetime :reset_at
      t.datetime :created_at, null: false
    end
    add_index :daily_ai_usage, [:site_id, :usage_date], unique: true

    # Master tables (integer PK, lookup only)
    create_table :event_types do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :event_types, :name, unique: true

    create_table :channel_types do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :channel_types, :name, unique: true

    create_table :alert_metric_types do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :alert_metric_types, :name, unique: true

    create_table :cwv_metric_types do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :cwv_metric_types, :name, unique: true

    create_table :recommendation_categories do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :recommendation_categories, :name, unique: true

    create_table :age_groups do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :age_groups, :name, unique: true
  end
end
