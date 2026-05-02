# frozen_string_literal: true

# [SEC.11] Lorenz Seed Provenance — schema additions for hybrid A+B+D design.
#
# Backend and firmware now derive the Lorenz attractor starting point
# (x₀, y₀, z₀) from a per-device K_seed instead of the publicly broadcast
# DID. K_seed is stored alongside the AES key on `hardware_keys`. Every
# `TelemetryLog` records the (x, y, z) tail of the trajectory plus a
# `cold_start_flag` so the next packet's continuation derivation knows
# whether to re-derive from K_seed (cold start, rare) or chain from the
# previous log (steady state).
#
# Design SSOT historically lived at docs/03_06_Lorenz_Seed_Provenance.md;
# after implementation that document is dissolved into 03_04 / 03_05 /
# 04_02 / 05_02. See `docs/10_02_Action_Plan_Tracker.md#SEC.11`.
class AddLorenzSeedProvenanceColumns < ActiveRecord::Migration[8.1]
  def change
    # Per-device 32-byte HKDF-derived secret. Shielded by ActiveRecord
    # Encryption (non-deterministic) at rest, exactly like aes_key_hex.
    add_column :hardware_keys, :lorenz_seed_hex, :string

    # PostgreSQL ADD COLUMN on a partitioned table cascades to every
    # attached partition (default + month buckets), so a single ALTER
    # is sufficient.
    add_column :telemetry_logs, :lorenz_state_x, :float
    add_column :telemetry_logs, :lorenz_state_y, :float
    add_column :telemetry_logs, :lorenz_state_z, :float
    add_column :telemetry_logs, :cold_start_flag, :boolean,
               default: false, null: false
  end
end
