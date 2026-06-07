# frozen_string_literal: true

# [L1 QATT] Trust-origin L1 — Queen-attestation маркери (канон: 05_02 ladder).
#
# gateways.last_attested_at  — коли шлюз востаннє довів Ed25519-походження батча
#                              (Grafana: attested-флот vs L0-флот).
# telemetry_logs.gateway_attested — per-record походження: рядок приїхав під
#                              валідним підписом Королеви. telemetry_logs
#                              партиційована (RANGE по created_at) — ADD COLUMN
#                              з DEFAULT на PG16 metadata-only (без rewrite),
#                              каскадується на всі партиції.
class AddL1AttestationMarkers < ActiveRecord::Migration[8.1]
  def change
    add_column :gateways, :last_attested_at, :timestamp
    add_column :telemetry_logs, :gateway_attested, :boolean, default: false, null: false
  end
end
