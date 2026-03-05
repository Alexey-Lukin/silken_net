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

ActiveRecord::Schema[8.1].define(version: 2026_03_05_132625) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "actuator_commands", force: :cascade do |t|
    t.bigint "actuator_id", null: false
    t.text "command_payload", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.text "error_message"
    t.bigint "ews_alert_id"
    t.datetime "executed_at"
    t.datetime "sent_at"
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["actuator_id"], name: "index_actuator_commands_on_actuator_id"
    t.index ["ews_alert_id"], name: "index_actuator_commands_on_ews_alert_id"
    t.index ["user_id"], name: "index_actuator_commands_on_user_id"
  end

  create_table "actuators", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "device_type"
    t.string "endpoint"
    t.bigint "gateway_id", null: false
    t.datetime "last_activated_at"
    t.string "name"
    t.integer "state"
    t.datetime "updated_at", null: false
    t.index ["gateway_id"], name: "index_actuators_on_gateway_id"
  end

  create_table "ai_insights", force: :cascade do |t|
    t.bigint "analyzable_id"
    t.string "analyzable_type"
    t.date "analyzed_date"
    t.decimal "average_temperature"
    t.datetime "created_at", null: false
    t.boolean "fraud_detected", default: false, null: false
    t.integer "insight_type"
    t.jsonb "prediction_data"
    t.decimal "probability_score"
    t.jsonb "reasoning"
    t.jsonb "recommendation"
    t.decimal "stress_index"
    t.text "summary"
    t.date "target_date"
    t.integer "total_growth_points"
    t.datetime "updated_at", null: false
    t.index ["analyzable_type", "analyzable_id", "target_date", "insight_type"], name: "idx_ai_insights_unique_report", unique: true
    t.index ["analyzable_type", "analyzable_id"], name: "index_ai_insights_on_analyzable"
    t.index ["reasoning"], name: "idx_ai_insights_reasoning_gin", using: :gin
    t.index ["target_date"], name: "idx_ai_insights_target_date"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "auditable_id"
    t.string "auditable_type"
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}
    t.bigint "organization_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["auditable_type", "auditable_id"], name: "index_audit_logs_on_auditable"
    t.index ["organization_id"], name: "index_audit_logs_on_organization_id"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "bio_contract_firmwares", force: :cascade do |t|
    t.text "bytecode_payload"
    t.datetime "created_at", null: false
    t.boolean "is_active"
    t.datetime "updated_at", null: false
    t.string "version"
  end

  create_table "blockchain_transactions", force: :cascade do |t|
    t.decimal "amount"
    t.bigint "block_number", comment: "Block number where transaction was included"
    t.bigint "cluster_id"
    t.datetime "confirmed_at", comment: "Timestamp when transaction was confirmed on-chain"
    t.datetime "created_at", null: false
    t.decimal "cumulative_gas_cost", comment: "Total gas cost in MATIC/POL (gas_price * gas_used)"
    t.text "error_message"
    t.decimal "gas_price", comment: "Gas price in wei at time of transaction"
    t.decimal "gas_used", comment: "Gas units consumed by the transaction"
    t.integer "locked_points"
    t.integer "nonce", comment: "EVM transaction nonce for idempotency"
    t.text "notes"
    t.datetime "sent_at", comment: "Timestamp when transaction was broadcast to mempool"
    t.bigint "sourceable_id"
    t.string "sourceable_type"
    t.integer "status"
    t.string "to_address"
    t.integer "token_type"
    t.string "tx_hash"
    t.datetime "updated_at", null: false
    t.bigint "wallet_id"
    t.index ["block_number"], name: "index_blockchain_transactions_on_block_number"
    t.index ["cluster_id"], name: "index_blockchain_transactions_on_cluster_id"
    t.index ["confirmed_at"], name: "index_blockchain_transactions_on_confirmed_at"
    t.index ["sourceable_type", "sourceable_id"], name: "index_blockchain_transactions_on_sourceable"
    t.index ["wallet_id"], name: "index_blockchain_transactions_on_wallet_id"
  end

  create_table "clusters", force: :cascade do |t|
    t.string "climate_type"
    t.datetime "created_at", null: false
    t.jsonb "environmental_settings"
    t.jsonb "geojson_polygon"
    t.float "health_index"
    t.string "name"
    t.bigint "organization_id"
    t.string "region"
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_clusters_on_organization_id"
  end

  create_table "device_calibrations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "impedance_offset_ohms"
    t.decimal "temperature_offset_c"
    t.bigint "tree_id", null: false
    t.datetime "updated_at", null: false
    t.decimal "vcap_coefficient", default: "1.0"
    t.index ["tree_id"], name: "index_device_calibrations_on_tree_id"
  end

  create_table "ews_alerts", force: :cascade do |t|
    t.integer "alert_type"
    t.bigint "cluster_id", null: false
    t.datetime "created_at", null: false
    t.text "message"
    t.text "resolution_notes"
    t.datetime "resolved_at"
    t.bigint "resolved_by"
    t.integer "severity"
    t.integer "status"
    t.bigint "tree_id"
    t.datetime "updated_at", null: false
    t.index ["cluster_id"], name: "index_ews_alerts_on_cluster_id"
    t.index ["resolved_at"], name: "index_ews_alerts_on_resolved_at"
    t.index ["tree_id"], name: "index_ews_alerts_on_tree_id"
  end

  create_table "gateway_telemetry_logs", force: :cascade do |t|
    t.integer "cellular_signal_csq"
    t.datetime "created_at", null: false
    t.bigint "gateway_id", null: false
    t.string "queen_uid"
    t.decimal "temperature_c"
    t.datetime "updated_at", null: false
    t.decimal "voltage_mv"
    t.index ["gateway_id"], name: "index_gateway_telemetry_logs_on_gateway_id"
  end

  create_table "gateways", force: :cascade do |t|
    t.decimal "altitude"
    t.bigint "cluster_id", null: false
    t.integer "config_sleep_interval_s"
    t.datetime "created_at", null: false
    t.string "firmware_version"
    t.string "ip_address"
    t.datetime "last_seen_at"
    t.integer "latest_voltage_mv"
    t.decimal "latitude"
    t.decimal "longitude"
    t.integer "state"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["cluster_id"], name: "index_gateways_on_cluster_id"
    t.index ["uid"], name: "index_gateways_on_uid", unique: true
  end

  create_table "hardware_keys", force: :cascade do |t|
    t.string "aes_key_hex"
    t.datetime "created_at", null: false
    t.string "device_uid"
    t.string "previous_aes_key_hex"
    t.datetime "rotated_at"
    t.datetime "updated_at", null: false
    t.index ["device_uid"], name: "index_hardware_keys_on_device_uid", unique: true
  end

  create_table "identities", force: :cascade do |t|
    t.string "access_token"
    t.jsonb "auth_data"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "provider"
    t.string "refresh_token"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_identities_on_user_id"
  end

  create_table "maintenance_records", force: :cascade do |t|
    t.integer "action_type"
    t.datetime "created_at", null: false
    t.bigint "ews_alert_id"
    t.bigint "maintainable_id"
    t.string "maintainable_type"
    t.text "notes"
    t.datetime "performed_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["ews_alert_id"], name: "index_maintenance_records_on_ews_alert_id"
    t.index ["maintainable_type", "maintainable_id"], name: "index_maintenance_records_on_maintainable"
    t.index ["user_id"], name: "index_maintenance_records_on_user_id"
  end

  create_table "naas_contracts", force: :cascade do |t|
    t.bigint "cluster_id", null: false
    t.datetime "created_at", null: false
    t.decimal "emitted_tokens", default: "0.0"
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
    t.integer "token_type", default: 0, null: false
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

  create_table "telemetry_logs", primary_key: ["id", "created_at"], options: "PARTITION BY RANGE (created_at)", force: :cascade do |t|
    t.integer "acoustic_events"
    t.integer "bio_status"
    t.datetime "created_at", null: false
    t.bigint "firmware_version_id"
    t.decimal "growth_points"
    t.bigserial "id", null: false
    t.integer "mesh_ttl"
    t.integer "metabolism_s"
    t.integer "piezo_voltage_mv"
    t.string "queen_uid"
    t.integer "rssi"
    t.boolean "tamper_detected"
    t.decimal "temperature_c"
    t.bigint "tree_id", null: false
    t.datetime "updated_at", null: false
    t.integer "voltage_mv"
    t.decimal "z_value"
    t.index ["bio_status", "created_at"], name: "idx_telemetry_logs_bio_status_created"
    t.index ["piezo_voltage_mv", "created_at"], name: "idx_telemetry_logs_piezo_created"
    t.index ["tree_id", "created_at"], name: "index_telemetry_logs_on_tree_id_and_created_at"
    t.index ["tree_id"], name: "index_telemetry_logs_on_tree_id"
  end

  create_table "telemetry_logs_default", primary_key: ["id", "created_at"], options: "INHERITS (telemetry_logs)", force: :cascade do |t|
    t.integer "acoustic_events"
    t.integer "bio_status"
    t.datetime "created_at", null: false
    t.bigint "firmware_version_id"
    t.decimal "growth_points"
    t.bigint "id", default: -> { "nextval('telemetry_logs_id_seq'::regclass)" }, null: false
    t.integer "mesh_ttl"
    t.integer "metabolism_s"
    t.integer "piezo_voltage_mv"
    t.string "queen_uid"
    t.integer "rssi"
    t.boolean "tamper_detected"
    t.decimal "temperature_c"
    t.bigint "tree_id", null: false
    t.datetime "updated_at", null: false
    t.integer "voltage_mv"
    t.decimal "z_value"
    t.index ["bio_status", "created_at"], name: "telemetry_logs_default_bio_status_created_at_idx"
    t.index ["piezo_voltage_mv", "created_at"], name: "telemetry_logs_default_piezo_voltage_mv_created_at_idx"
    t.index ["tree_id", "created_at"], name: "telemetry_logs_default_tree_id_created_at_idx"
    t.index ["tree_id"], name: "telemetry_logs_default_tree_id_idx"
  end

  create_table "telemetry_logs_y2026m01", primary_key: ["id", "created_at"], options: "INHERITS (telemetry_logs)", force: :cascade do |t|
    t.integer "acoustic_events"
    t.integer "bio_status"
    t.datetime "created_at", null: false
    t.bigint "firmware_version_id"
    t.decimal "growth_points"
    t.bigint "id", default: -> { "nextval('telemetry_logs_id_seq'::regclass)" }, null: false
    t.integer "mesh_ttl"
    t.integer "metabolism_s"
    t.integer "piezo_voltage_mv"
    t.string "queen_uid"
    t.integer "rssi"
    t.boolean "tamper_detected"
    t.decimal "temperature_c"
    t.bigint "tree_id", null: false
    t.datetime "updated_at", null: false
    t.integer "voltage_mv"
    t.decimal "z_value"
    t.index ["bio_status", "created_at"], name: "telemetry_logs_y2026m01_bio_status_created_at_idx"
    t.index ["piezo_voltage_mv", "created_at"], name: "telemetry_logs_y2026m01_piezo_voltage_mv_created_at_idx"
    t.index ["tree_id", "created_at"], name: "telemetry_logs_y2026m01_tree_id_created_at_idx"
    t.index ["tree_id"], name: "telemetry_logs_y2026m01_tree_id_idx"
  end

  create_table "telemetry_logs_y2026m02", primary_key: ["id", "created_at"], options: "INHERITS (telemetry_logs)", force: :cascade do |t|
    t.integer "acoustic_events"
    t.integer "bio_status"
    t.datetime "created_at", null: false
    t.bigint "firmware_version_id"
    t.decimal "growth_points"
    t.bigint "id", default: -> { "nextval('telemetry_logs_id_seq'::regclass)" }, null: false
    t.integer "mesh_ttl"
    t.integer "metabolism_s"
    t.integer "piezo_voltage_mv"
    t.string "queen_uid"
    t.integer "rssi"
    t.boolean "tamper_detected"
    t.decimal "temperature_c"
    t.bigint "tree_id", null: false
    t.datetime "updated_at", null: false
    t.integer "voltage_mv"
    t.decimal "z_value"
    t.index ["bio_status", "created_at"], name: "telemetry_logs_y2026m02_bio_status_created_at_idx"
    t.index ["piezo_voltage_mv", "created_at"], name: "telemetry_logs_y2026m02_piezo_voltage_mv_created_at_idx"
    t.index ["tree_id", "created_at"], name: "telemetry_logs_y2026m02_tree_id_created_at_idx"
    t.index ["tree_id"], name: "telemetry_logs_y2026m02_tree_id_idx"
  end

  create_table "telemetry_logs_y2026m03", primary_key: ["id", "created_at"], options: "INHERITS (telemetry_logs)", force: :cascade do |t|
    t.integer "acoustic_events"
    t.integer "bio_status"
    t.datetime "created_at", null: false
    t.bigint "firmware_version_id"
    t.decimal "growth_points"
    t.bigint "id", default: -> { "nextval('telemetry_logs_id_seq'::regclass)" }, null: false
    t.integer "mesh_ttl"
    t.integer "metabolism_s"
    t.integer "piezo_voltage_mv"
    t.string "queen_uid"
    t.integer "rssi"
    t.boolean "tamper_detected"
    t.decimal "temperature_c"
    t.bigint "tree_id", null: false
    t.datetime "updated_at", null: false
    t.integer "voltage_mv"
    t.decimal "z_value"
    t.index ["bio_status", "created_at"], name: "telemetry_logs_y2026m03_bio_status_created_at_idx"
    t.index ["piezo_voltage_mv", "created_at"], name: "telemetry_logs_y2026m03_piezo_voltage_mv_created_at_idx"
    t.index ["tree_id", "created_at"], name: "telemetry_logs_y2026m03_tree_id_created_at_idx"
    t.index ["tree_id"], name: "telemetry_logs_y2026m03_tree_id_idx"
  end

  create_table "telemetry_logs_y2026m04", primary_key: ["id", "created_at"], options: "INHERITS (telemetry_logs)", force: :cascade do |t|
    t.integer "acoustic_events"
    t.integer "bio_status"
    t.datetime "created_at", null: false
    t.bigint "firmware_version_id"
    t.decimal "growth_points"
    t.bigint "id", default: -> { "nextval('telemetry_logs_id_seq'::regclass)" }, null: false
    t.integer "mesh_ttl"
    t.integer "metabolism_s"
    t.integer "piezo_voltage_mv"
    t.string "queen_uid"
    t.integer "rssi"
    t.boolean "tamper_detected"
    t.decimal "temperature_c"
    t.bigint "tree_id", null: false
    t.datetime "updated_at", null: false
    t.integer "voltage_mv"
    t.decimal "z_value"
    t.index ["bio_status", "created_at"], name: "telemetry_logs_y2026m04_bio_status_created_at_idx"
    t.index ["piezo_voltage_mv", "created_at"], name: "telemetry_logs_y2026m04_piezo_voltage_mv_created_at_idx"
    t.index ["tree_id", "created_at"], name: "telemetry_logs_y2026m04_tree_id_created_at_idx"
    t.index ["tree_id"], name: "telemetry_logs_y2026m04_tree_id_idx"
  end

  create_table "telemetry_logs_y2026m05", primary_key: ["id", "created_at"], options: "INHERITS (telemetry_logs)", force: :cascade do |t|
    t.integer "acoustic_events"
    t.integer "bio_status"
    t.datetime "created_at", null: false
    t.bigint "firmware_version_id"
    t.decimal "growth_points"
    t.bigint "id", default: -> { "nextval('telemetry_logs_id_seq'::regclass)" }, null: false
    t.integer "mesh_ttl"
    t.integer "metabolism_s"
    t.integer "piezo_voltage_mv"
    t.string "queen_uid"
    t.integer "rssi"
    t.boolean "tamper_detected"
    t.decimal "temperature_c"
    t.bigint "tree_id", null: false
    t.datetime "updated_at", null: false
    t.integer "voltage_mv"
    t.decimal "z_value"
    t.index ["bio_status", "created_at"], name: "telemetry_logs_y2026m05_bio_status_created_at_idx"
    t.index ["piezo_voltage_mv", "created_at"], name: "telemetry_logs_y2026m05_piezo_voltage_mv_created_at_idx"
    t.index ["tree_id", "created_at"], name: "telemetry_logs_y2026m05_tree_id_created_at_idx"
    t.index ["tree_id"], name: "telemetry_logs_y2026m05_tree_id_idx"
  end

  create_table "telemetry_logs_y2026m06", primary_key: ["id", "created_at"], options: "INHERITS (telemetry_logs)", force: :cascade do |t|
    t.integer "acoustic_events"
    t.integer "bio_status"
    t.datetime "created_at", null: false
    t.bigint "firmware_version_id"
    t.decimal "growth_points"
    t.bigint "id", default: -> { "nextval('telemetry_logs_id_seq'::regclass)" }, null: false
    t.integer "mesh_ttl"
    t.integer "metabolism_s"
    t.integer "piezo_voltage_mv"
    t.string "queen_uid"
    t.integer "rssi"
    t.boolean "tamper_detected"
    t.decimal "temperature_c"
    t.bigint "tree_id", null: false
    t.datetime "updated_at", null: false
    t.integer "voltage_mv"
    t.decimal "z_value"
    t.index ["bio_status", "created_at"], name: "telemetry_logs_y2026m06_bio_status_created_at_idx"
    t.index ["piezo_voltage_mv", "created_at"], name: "telemetry_logs_y2026m06_piezo_voltage_mv_created_at_idx"
    t.index ["tree_id", "created_at"], name: "telemetry_logs_y2026m06_tree_id_created_at_idx"
    t.index ["tree_id"], name: "telemetry_logs_y2026m06_tree_id_idx"
  end

  create_table "tiny_ml_models", force: :cascade do |t|
    t.text "binary_weights_payload"
    t.string "checksum"
    t.datetime "created_at", null: false
    t.boolean "is_active", default: false
    t.jsonb "metadata"
    t.string "target_pest"
    t.bigint "tree_family_id"
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["tree_family_id"], name: "index_tiny_ml_models_on_tree_family_id"
  end

  create_table "tree_families", force: :cascade do |t|
    t.integer "baseline_impedance"
    t.jsonb "biological_properties"
    t.float "carbon_sequestration_coefficient", default: 1.0, null: false
    t.datetime "created_at", null: false
    t.decimal "critical_z_max"
    t.decimal "critical_z_min"
    t.string "name"
    t.string "scientific_name"
    t.datetime "updated_at", null: false
    t.index ["scientific_name"], name: "index_tree_families_on_scientific_name", unique: true, where: "(scientific_name IS NOT NULL)"
  end

  create_table "trees", force: :cascade do |t|
    t.decimal "altitude"
    t.bigint "cluster_id"
    t.datetime "created_at", null: false
    t.string "did"
    t.string "firmware_version"
    t.integer "health_streak", default: 0, null: false
    t.datetime "last_seen_at"
    t.integer "latest_voltage_mv"
    t.decimal "latitude"
    t.decimal "longitude"
    t.integer "status", default: 0
    t.bigint "tiny_ml_model_id"
    t.bigint "tree_family_id", null: false
    t.datetime "updated_at", null: false
    t.index ["cluster_id"], name: "index_trees_on_cluster_id"
    t.index ["did"], name: "index_trees_on_did", unique: true
    t.index ["status"], name: "index_trees_on_status"
    t.index ["tiny_ml_model_id"], name: "index_trees_on_tiny_ml_model_id"
    t.index ["tree_family_id"], name: "index_trees_on_tree_family_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address"
    t.string "first_name"
    t.string "last_name"
    t.datetime "last_seen_at"
    t.bigint "organization_id"
    t.string "password_digest"
    t.string "phone_number"
    t.integer "role"
    t.string "telegram_chat_id"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["last_seen_at"], name: "index_users_on_last_seen_at"
    t.index ["organization_id", "last_seen_at", "id"], name: "index_users_on_org_last_seen_id", order: { last_seen_at: :desc, id: :desc }
    t.index ["organization_id"], name: "index_users_on_organization_id"
  end

  create_table "wallets", force: :cascade do |t|
    t.decimal "balance"
    t.datetime "created_at", null: false
    t.string "crypto_public_address"
    t.bigint "organization_id"
    t.bigint "tree_id", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_wallets_on_organization_id"
    t.index ["tree_id"], name: "index_wallets_on_tree_id"
  end

  add_foreign_key "actuator_commands", "actuators"
  add_foreign_key "actuator_commands", "ews_alerts"
  add_foreign_key "actuator_commands", "users"
  add_foreign_key "actuators", "gateways"
  add_foreign_key "audit_logs", "organizations"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "blockchain_transactions", "clusters"
  add_foreign_key "blockchain_transactions", "wallets"
  add_foreign_key "clusters", "organizations"
  add_foreign_key "device_calibrations", "trees"
  add_foreign_key "ews_alerts", "clusters"
  add_foreign_key "ews_alerts", "trees"
  add_foreign_key "ews_alerts", "users", column: "resolved_by"
  add_foreign_key "gateway_telemetry_logs", "gateways"
  add_foreign_key "gateways", "clusters"
  add_foreign_key "identities", "users"
  add_foreign_key "maintenance_records", "ews_alerts"
  add_foreign_key "maintenance_records", "users"
  add_foreign_key "naas_contracts", "clusters"
  add_foreign_key "naas_contracts", "organizations"
  add_foreign_key "parametric_insurances", "clusters"
  add_foreign_key "parametric_insurances", "organizations"
  add_foreign_key "sessions", "users"
  add_foreign_key "telemetry_logs", "trees", name: "fk_telemetry_logs_tree_id"
  add_foreign_key "telemetry_logs_default", "trees", name: "fk_telemetry_logs_tree_id"
  add_foreign_key "telemetry_logs_y2026m01", "trees", name: "fk_telemetry_logs_tree_id"
  add_foreign_key "telemetry_logs_y2026m02", "trees", name: "fk_telemetry_logs_tree_id"
  add_foreign_key "telemetry_logs_y2026m03", "trees", name: "fk_telemetry_logs_tree_id"
  add_foreign_key "telemetry_logs_y2026m04", "trees", name: "fk_telemetry_logs_tree_id"
  add_foreign_key "telemetry_logs_y2026m05", "trees", name: "fk_telemetry_logs_tree_id"
  add_foreign_key "telemetry_logs_y2026m06", "trees", name: "fk_telemetry_logs_tree_id"
  add_foreign_key "tiny_ml_models", "tree_families"
  add_foreign_key "trees", "clusters"
  add_foreign_key "trees", "tiny_ml_models"
  add_foreign_key "trees", "tree_families"
  add_foreign_key "users", "organizations"
  add_foreign_key "wallets", "organizations"
  add_foreign_key "wallets", "trees"
end
