# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_06_30_000002) do
  create_table "age_groups", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_age_groups_on_name", unique: true
  end

  create_table "ai_recommendations", id: :string, force: :cascade do |t|
    t.string "site_id", null: false
    t.string "category"
    t.integer "priority"
    t.text "description"
    t.string "estimated_impact"
    t.datetime "generated_at"
    t.datetime "created_at", null: false
    t.index ["site_id"], name: "index_ai_recommendations_on_site_id"
  end

  create_table "alert_logs", id: :string, force: :cascade do |t|
    t.string "alert_rule_id", null: false
    t.datetime "fired_at", null: false
    t.decimal "metric_value", precision: 12, scale: 4, null: false
    t.datetime "created_at", null: false
    t.index ["alert_rule_id"], name: "index_alert_logs_on_alert_rule_id"
  end

  create_table "alert_metric_types", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_alert_metric_types_on_name", unique: true
  end

  create_table "alert_rules", id: :string, force: :cascade do |t|
    t.string "site_id", null: false
    t.string "metric"
    t.string "condition"
    t.decimal "threshold", precision: 12, scale: 4
    t.integer "cooldown_min", default: 60
    t.datetime "last_fired_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id"], name: "index_alert_rules_on_site_id"
  end

  create_table "channel_types", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_channel_types_on_name", unique: true
  end

  create_table "cwv_metric_types", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_cwv_metric_types_on_name", unique: true
  end

  create_table "daily_ai_usage", id: :string, force: :cascade do |t|
    t.string "site_id", null: false
    t.date "usage_date", null: false
    t.integer "used_count", default: 0, null: false
    t.datetime "reset_at"
    t.datetime "created_at", null: false
    t.index ["site_id", "usage_date"], name: "index_daily_ai_usage_on_site_id_and_usage_date", unique: true
    t.index ["site_id"], name: "index_daily_ai_usage_on_site_id"
  end

  create_table "event_types", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_event_types_on_name", unique: true
  end

  create_table "events", id: :string, force: :cascade do |t|
    t.string "site_id", null: false
    t.string "session_id", null: false
    t.string "event_type", null: false
    t.string "page_url"
    t.string "referrer"
    t.string "user_agent"
    t.json "properties"
    t.decimal "x_ratio", precision: 5, scale: 4
    t.decimal "y_ratio", precision: 5, scale: 4
    t.boolean "is_bot", default: false, null: false
    t.datetime "occurred_at"
    t.datetime "created_at", null: false
    t.index ["occurred_at"], name: "index_events_on_occurred_at"
    t.index ["session_id"], name: "index_events_on_session_id"
    t.index ["site_id"], name: "index_events_on_site_id"
  end

  create_table "funnels", id: :string, force: :cascade do |t|
    t.string "site_id", null: false
    t.string "name", null: false
    t.json "steps"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id"], name: "index_funnels_on_site_id"
  end

  create_table "recommendation_categories", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_recommendation_categories_on_name", unique: true
  end

  create_table "sessions", id: :string, force: :cascade do |t|
    t.string "site_id", null: false
    t.string "fingerprint", null: false
    t.string "channel"
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_campaign"
    t.boolean "is_bot", default: false, null: false
    t.datetime "started_at"
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.index ["site_id"], name: "index_sessions_on_site_id"
  end

  create_table "sites", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "name", null: false
    t.string "url", null: false
    t.string "api_key", null: false
    t.boolean "verified", default: false, null: false
    t.string "verify_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key"], name: "index_sites_on_api_key", unique: true
    t.index ["user_id"], name: "index_sites_on_user_id"
  end

  create_table "users", id: :string, force: :cascade do |t|
    t.string "google_sub", null: false
    t.string "display_name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["google_sub"], name: "index_users_on_google_sub", unique: true
  end

  create_table "web_vitals", id: :string, force: :cascade do |t|
    t.string "site_id", null: false
    t.string "session_id", null: false
    t.string "page_url"
    t.integer "lcp_ms"
    t.integer "fid_ms"
    t.decimal "cls_score", precision: 6, scale: 4
    t.integer "ttfb_ms"
    t.integer "fcp_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_web_vitals_on_session_id"
    t.index ["site_id"], name: "index_web_vitals_on_site_id"
  end

  add_foreign_key "ai_recommendations", "sites"
  add_foreign_key "alert_logs", "alert_rules"
  add_foreign_key "alert_rules", "sites"
  add_foreign_key "daily_ai_usage", "sites"
  add_foreign_key "events", "sessions"
  add_foreign_key "events", "sites"
  add_foreign_key "funnels", "sites"
  add_foreign_key "sessions", "sites"
  add_foreign_key "sites", "users"
  add_foreign_key "web_vitals", "sessions"
  add_foreign_key "web_vitals", "sites"
end
