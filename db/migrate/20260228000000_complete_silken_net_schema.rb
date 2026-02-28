# frozen_string_literal: true

class CompleteSilkenNetSchema < ActiveRecord::Migration[8.1]
  def change
    # =====================================================================
    # USERS - columns not covered by 20260227220000
    # =====================================================================
    change_table :users do |t|
      t.string :first_name
      t.string :last_name
      t.string :telegram_chat_id
    end

    change_column_null :users, :organization_id, true

    # =====================================================================
    # CLUSTERS - add organization FK
    # =====================================================================
    add_reference :clusters, :organization, foreign_key: true

    # =====================================================================
    # TREES - remaining columns
    # =====================================================================
    change_table :trees do |t|
      t.datetime :last_seen_at
      t.string :firmware_version
    end

    change_column_null :trees, :cluster_id, true
    change_column_null :trees, :tiny_ml_model_id, true

    # =====================================================================
    # GATEWAYS
    # =====================================================================
    change_table :gateways do |t|
      t.integer :state
      t.string :firmware_version
    end

    # =====================================================================
    # EWS_ALERTS - remaining columns (resolved_at already added by 20260227)
    # =====================================================================
    change_table :ews_alerts do |t|
      t.integer :status
      t.bigint :resolved_by
      t.text :resolution_notes
    end

    change_column_null :ews_alerts, :tree_id, true
    add_foreign_key :ews_alerts, :users, column: :resolved_by

    # =====================================================================
    # ACTUATORS - add endpoint
    # =====================================================================
    add_column :actuators, :endpoint, :string

    # =====================================================================
    # ACTUATOR_COMMANDS (new table)
    # =====================================================================
    create_table :actuator_commands do |t|
      t.references :actuator, null: false, foreign_key: true
      t.references :ews_alert, foreign_key: true
      t.references :user, foreign_key: true
      t.text :command_payload, null: false
      t.integer :duration_seconds
      t.integer :status, default: 0
      t.datetime :sent_at
      t.datetime :executed_at
      t.text :error_message
      t.timestamps
    end

    # =====================================================================
    # BLOCKCHAIN_TRANSACTIONS
    # =====================================================================
    change_table :blockchain_transactions do |t|
      t.string :to_address
      t.text :error_message
      t.bigint :sourceable_id
      t.string :sourceable_type
    end

    add_index :blockchain_transactions, [:sourceable_type, :sourceable_id],
              name: "index_blockchain_transactions_on_sourceable"

    # =====================================================================
    # IDENTITIES
    # =====================================================================
    change_table :identities do |t|
      t.string :access_token
      t.string :refresh_token
      t.jsonb :auth_data
      t.datetime :expires_at
    end

    # =====================================================================
    # TINY_ML_MODELS
    # =====================================================================
    change_table :tiny_ml_models do |t|
      t.string :checksum
      t.boolean :is_active, default: false
      t.jsonb :metadata
      t.references :tree_family, foreign_key: true
    end

    # =====================================================================
    # MAINTENANCE_RECORDS
    # =====================================================================
    rename_column :maintenance_records, :action_taken, :notes
    add_reference :maintenance_records, :ews_alert, foreign_key: true

    # =====================================================================
    # TELEMETRY_LOGS
    # =====================================================================
    add_column :telemetry_logs, :firmware_version_id, :bigint

    # =====================================================================
    # NAAS_CONTRACTS
    # =====================================================================
    add_column :naas_contracts, :emitted_tokens, :decimal, default: 0

    # =====================================================================
    # AI_INSIGHTS - add recommendation (analyzable + others done by 20260227)
    # =====================================================================
    add_column :ai_insights, :recommendation, :jsonb

    # =====================================================================
    # GATEWAY_TELEMETRY_LOGS
    # =====================================================================
    rename_column :gateway_telemetry_logs, :battery_level, :voltage_mv
    rename_column :gateway_telemetry_logs, :signal_strength, :cellular_signal_csq
    add_column :gateway_telemetry_logs, :temperature_c, :decimal

    # =====================================================================
    # BIO_CONTRACT_FIRMWARES
    # =====================================================================
    rename_column :bio_contract_firmwares, :binary_payload, :bytecode_payload

    # =====================================================================
    # TREE_FAMILIES
    # =====================================================================
    add_column :tree_families, :biological_properties, :jsonb
  end
end
