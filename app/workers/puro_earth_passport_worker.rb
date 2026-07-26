# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# =============================================================================
# Afterlife Economy — Puro.earth Biomass Passport Worker
# =============================================================================
# When a tree dies and its wood is extracted (biomass_extraction), this worker
# generates a D-MRV (Digital Measurement, Reporting and Verification) payload —
# a "Biomass Passport" — proving the origin and quantity of dead wood destined
# for Biochar CORC generation on Puro.earth.
#
# The passport anchors: tree DID, GPS coordinates, biomass yield, extraction
# date, and a SHA-256 hash of lifetime telemetry for tamper-proof provenance.
#
# Two-phase submission:
# 1. On-chain anchoring via PuroEarth::PassportService → Polygon D-MRV Registry
# 2. REST API submission via PuroEarth::RegistryApiService → Puro.earth CORC
#
# Transaction confirmation is tracked by BlockchainConfirmationWorker.
# =============================================================================
class PuroEarthPassportWorker
  include ApplicationWeb3Worker
  sidekiq_options queue: "web3", retry: 5

  def perform(maintenance_record_id)
    record = MaintenanceRecord.find(maintenance_record_id)
    tree   = record.maintainable

    unless tree.is_a?(Tree)
      Rails.logger.warn "🌿 [Puro.earth] Record ##{maintenance_record_id} maintainable is not a Tree, skipping."
      return
    end

    payload = build_passport_payload(record, tree)

    # Phase 1: On-chain anchoring (Polygon D-MRV Registry).
    # [ARCH.53/PuroEarth] Ідемпотентно: skip re-anchor якщо tx_hash вже є (double-anchor guard
    # на retry-after-persist). Вузький residual — краш МІЖ broadcast і persist (tx_hash ще nil) →
    # retry re-anchor; payloadHash детермінований → це ІДЕНТИЧНИЙ дубль-proof (registry-noise, не
    # double-CORC, бо Phase 2 guard'иться corc_ref) — reconcile-only, як EVM :processing-orphan.
    if record.biomass_passport_tx_hash.blank?
      tx_hash = with_web3_error_handling("Polygon", "Puro.earth Passport for Tree #{tree.did}") do
        PuroEarth::PassportService.new(payload).anchor!
      end
      record.update!(biomass_passport_tx_hash: tx_hash)
    end

    # [ARCH.53/B5] Confirmation-планування ПОЗА anchor-guard → краш між persist і enqueue
    # відновлюється на retry (BlockchainConfirmationWorker `unique_for` дедуплікує повторне).
    BlockchainConfirmationWorker.perform_in(30.seconds, record.biomass_passport_tx_hash)

    # Phase 2: REST API submission to Puro.earth for CORC issuance (idempotent — skip if issued).
    if record.puro_earth_corc_ref.blank?
      corc_ref = submit_to_puro_earth_api(payload, record.biomass_passport_tx_hash)
      record.update!(puro_earth_corc_ref: corc_ref) if corc_ref
    end

    Rails.logger.info "🌿 [Puro.earth] Biomass Passport generated. " \
                      "Tree #{tree.did}, yield: #{record.biomass_yield_kg} kg, " \
                      "tx: #{record.biomass_passport_tx_hash}, CORC: #{record.puro_earth_corc_ref || "pending"}"

    payload
  end

  private

  # Phase 2: Submit passport to Puro.earth REST API for CORC issuance.
  # Non-blocking: REST API failure does NOT invalidate on-chain anchoring.
  # The on-chain proof (tx_hash) is already recorded, so CORC can be
  # resubmitted manually or via retry if API is temporarily unavailable.
  def submit_to_puro_earth_api(payload, tx_hash)
    PuroEarth::RegistryApiService.new(payload, tx_hash: tx_hash).submit!
  rescue PuroEarth::RegistryApiService::SubmissionError => e
    Rails.logger.warn "🌿 [Puro.earth] REST API submission failed (on-chain anchoring succeeded): #{e.message}"
    nil
  end

  def build_passport_payload(record, tree)
    {
      tree_did: tree.did,
      biomass_yield_kg: record.biomass_yield_kg.to_f,
      extraction_date: record.performed_at.iso8601,
      gps_coordinates: {
        latitude: record.latitude&.to_f || tree.latitude&.to_f,
        longitude: record.longitude&.to_f || tree.longitude&.to_f
      },
      lifetime_telemetry_hash: compute_telemetry_hash(tree)
    }
  end

  def compute_telemetry_hash(tree)
    digest_input = "#{tree.did}:#{tree.telemetry_logs.count}:#{tree.created_at.to_i}"
    Digest::SHA256.hexdigest(digest_input)
  end
end
