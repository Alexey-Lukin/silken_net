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

ActiveRecord::Schema[8.1].define(version: 2026_02_26_172704) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "actuators", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "device_type"
    t.bigint "gateway_id", null: false
    t.string "name"
    t.integer "state"
    t.datetime "updated_at", null: false
    t.index ["gateway_id"], name: "index_actuators_on_gateway_id"
  end

  create_table "ai_insights", force: :cascade do |t|
    t.bigint "cluster_id", null: false
    t.datetime "created_at", null: false
    t.integer "insight_type"
    t.jsonb "prediction_data"
    t.datetime "updated_at", null: false
    t.index ["cluster_id"], name: "index_ai_insights_on_cluster_id"
  end

  create_table "bio_contract_firmwares", force: :cascade do |t|
    t.text "binary_payload"
    t.datetime "created_at", null: false
    t.boolean "is_active"
    t.datetime "updated_at", null: false
    t.string "version"
  end

  create_table "blockchain_transactions", force: :cascade do |t|
    t.decimal "amount"
    t.datetime "created_at", null: false
    t.text "notes"
    t.integer "status"
    t.integer "token_type"
    t.string "tx_hash"
    t.datetime "updated_at", null: false
    t.bigint "wallet_id", null: false
    t.index ["wallet_id"], name: "index_blockchain_transactions_on_wallet_id"
  end

  create_table "clusters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.string "region"
    t.datetime "updated_at", null: false
  end

  create_table "device_calibrations", force: :cascade do |t|
    t.integer "acoustic_offset"
    t.datetime "created_at", null: false
    t.decimal "temp_offset"
    t.bigint "tree_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tree_id"], name: "index_device_calibrations_on_tree_id"
  end

  create_table "ews_alerts", force: :cascade do |t|
    t.integer "alert_type"
    t.bigint "cluster_id", null: false
    t.datetime "created_at", null: false
    t.text "message"
    t.integer "severity"
    t.bigint "tree_id", null: false
    t.datetime "updated_at", null: false
    t.index ["cluster_id"], name: "index_ews_alerts_on_cluster_id"
    t.index ["tree_id"], name: "index_ews_alerts_on_tree_id"
  end

  create_table "gateway_telemetry_logs", force: :cascade do |t|
    t.decimal "battery_level"
    t.datetime "created_at", null: false
    t.bigint "gateway_id", null: false
    t.string "queen_uid"
    t.integer "signal_strength"
    t.datetime "updated_at", null: false
    t.index ["gateway_id"], name: "index_gateway_telemetry_logs_on_gateway_id"
  end

  create_table "gateways", force: :cascade do |t|
    t.decimal "altitude"
    t.bigint "cluster_id", null: false
    t.integer "config_sleep_interval_s"
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "last_seen_at"
    t.decimal "latitude"
    t.decimal "longitude"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["cluster_id"], name: "index_gateways_on_cluster_id"
    t.index ["uid"], name: "index_gateways_on_uid", unique: true
  end

  create_table "hardware_keys", force: :cascade do |t|
    t.string "aes_key"
    t.datetime "created_at", null: false
    t.bigint "tree_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tree_id"], name: "index_hardware_keys_on_tree_id"
  end

  create_table "identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "provider"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_identities_on_user_id"
  end

  create_table "maintenance_records", force: :cascade do |t|
    t.text "action_taken"
    t.integer "action_type"
    t.datetime "created_at", null: false
    t.bigint "maintainable_id"
    t.string "maintainable_type"
    t.datetime "performed_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["maintainable_type", "maintainable_id"], name: "index_maintenance_records_on_maintainable"
    t.index ["user_id"], name: "index_maintenance_records_on_user_id"
  end

  create_table "naas_contracts", force: :cascade do |t|
    t.bigint "cluster_id", null: false
    t.datetime "created_at", null: false
    t.datetime "end_date"
    t.bigint "organization_id", null: false
    t.datetime "start_date"
    t.integer "status"
    t.decimal "total_funding"
    t.datetime "updated_at", null: false
    t.index ["cluster_id"], name: "index_naas_contracts_on_cluster_id"
    t.index ["organization_id"], name: "index_naas_contracts_on_organization_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "billing_email"
    t.datetime "created_at", null: false
    t.string "crypto_public_address"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "parametric_insurances", force: :cascade do |t|
    t.bigint "cluster_id", null: false
    t.datetime "created_at", null: false
    t.bigint "organization_id", null: false
    t.decimal "payout_amount"
    t.integer "status"
    t.decimal "threshold_value"
    t.integer "trigger_event"
    t.datetime "updated_at", null: false
    t.index ["cluster_id"], name: "index_parametric_insurances_on_cluster_id"
    t.index ["organization_id"], name: "index_parametric_insurances_on_organization_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "telemetry_logs", force: :cascade do |t|
    t.integer "acoustic_events"
    t.integer "bio_status"
    t.datetime "created_at", null: false
    t.decimal "growth_points"
    t.integer "mesh_ttl"
    t.integer "metabolism_s"
    t.integer "piezo_voltage_mv"
    t.string "queen_uid"
    t.boolean "tamper_detected"
    t.decimal "temperature_c"
    t.bigint "tree_id", null: false
    t.datetime "updated_at", null: false
    t.integer "voltage_mv"
    t.decimal "z_value"
    t.index ["tree_id"], name: "index_telemetry_logs_on_tree_id"
  end

  create_table "tiny_ml_models", force: :cascade do |t|
    t.text "binary_weights_payload"
    t.datetime "created_at", null: false
    t.string "target_pest"
    t.datetime "updated_at", null: false
    t.string "version"
  end

  create_table "tree_families", force: :cascade do |t|
    t.integer "baseline_impedance"
    t.datetime "created_at", null: false
    t.decimal "critical_z_max"
    t.decimal "critical_z_min"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "trees", force: :cascade do |t|
    t.decimal "altitude"
    t.bigint "cluster_id", null: false
    t.datetime "created_at", null: false
    t.string "did"
    t.decimal "latitude"
    t.decimal "longitude"
    t.bigint "tiny_ml_model_id", null: false
    t.bigint "tree_family_id", null: false
    t.datetime "updated_at", null: false
    t.index ["cluster_id"], name: "index_trees_on_cluster_id"
    t.index ["did"], name: "index_trees_on_did", unique: true
    t.index ["tiny_ml_model_id"], name: "index_trees_on_tiny_ml_model_id"
    t.index ["tree_family_id"], name: "index_trees_on_tree_family_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.bigint "organization_id", null: false
    t.string "password_digest"
    t.integer "role"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["organization_id"], name: "index_users_on_organization_id"
  end

  create_table "wallets", force: :cascade do |t|
    t.decimal "balance"
    t.datetime "created_at", null: false
    t.string "crypto_public_address"
    t.bigint "tree_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tree_id"], name: "index_wallets_on_tree_id"
  end

  add_foreign_key "actuators", "gateways"
  add_foreign_key "ai_insights", "clusters"
  add_foreign_key "blockchain_transactions", "wallets"
  add_foreign_key "device_calibrations", "trees"
  add_foreign_key "ews_alerts", "clusters"
  add_foreign_key "ews_alerts", "trees"
  add_foreign_key "gateway_telemetry_logs", "gateways"
  add_foreign_key "gateways", "clusters"
  add_foreign_key "hardware_keys", "trees"
  add_foreign_key "identities", "users"
  add_foreign_key "maintenance_records", "users"
  add_foreign_key "naas_contracts", "clusters"
  add_foreign_key "naas_contracts", "organizations"
  add_foreign_key "parametric_insurances", "clusters"
  add_foreign_key "parametric_insurances", "organizations"
  add_foreign_key "sessions", "users"
  add_foreign_key "telemetry_logs", "trees"
  add_foreign_key "trees", "clusters"
  add_foreign_key "trees", "tiny_ml_models"
  add_foreign_key "trees", "tree_families"
  add_foreign_key "users", "organizations"
  add_foreign_key "wallets", "trees"
end
