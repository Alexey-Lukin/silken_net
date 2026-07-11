# frozen_string_literal: true

# [ARCH.56] DB-level integrity backstops: кожен unique-індекс дзеркалить
# наявну Ruby-валідацію (race-вікно між SELECT і INSERT валідація не закриває),
# CHECK страхує money-інваріант від bypass через update_all/SQL.
# Пре-деплойне вікно: база порожня, DDL безкоштовний.
class AddArch56IntegrityBackstops < ActiveRecord::Migration[8.1]
  def change
    # Пре-деплой (перший деплой ще не відбувся): всі таблиці порожні, жодного
    # трафіку — lock-безпека concurrently тут не купує нічого.
    safety_assured { apply_backstops }
  end

  private

  def apply_backstops
    # -- (a) unique-індекси: дзеркала validates ... uniqueness ------------------
    add_index :organizations, :name, unique: true
    add_index :organizations, :crypto_public_address, unique: true
    add_index :clusters, :name, unique: true
    add_index :tree_families, :name, unique: true
    add_index :identities, [ :provider, :uid ], unique: true
    add_index :bio_contract_firmwares, :version, unique: true
    add_index :tiny_ml_models, :version, unique: true

    # Composite unique поглинає leading-роль старого FK-індексу (dedup).
    remove_index :actuators, :gateway_id
    add_index :actuators, [ :gateway_id, :endpoint ], unique: true

    # has_one :wallet / has_one :device_calibration — друга row = phantom.
    remove_index :wallets, :tree_id
    add_index :wallets, :tree_id, unique: true
    remove_index :device_calibrations, :tree_id
    add_index :device_calibrations, :tree_id, unique: true

    # -- (b) money-інваріант: locked ⊆ balance (Wallet#available_balance) ------
    add_check_constraint :wallets,
      "balance >= 0 AND locked_balance >= 0 AND esg_retired_balance >= 0 AND locked_balance <= balance",
      name: "wallets_balance_invariants"
    change_column :blockchain_transactions, :amount, :numeric, precision: 24, scale: 6

    # -- (c) AASM nil-state footgun: стан завжди визначений (initial :idle) ----
    change_column_default :gateways, :state, from: nil, to: 0
    change_column_null :gateways, :state, false, 0

    # -- (ARCH.59 pull-forward) OTA-watchdog якір: колонка дешева зараз,
    # zero-downtime-хореографія — після деплою. Watchdog-логіка = ARCH.59.
    add_column :gateways, :ota_started_at, :timestamptz
  end
end
