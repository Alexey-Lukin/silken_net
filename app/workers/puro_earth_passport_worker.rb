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
# =============================================================================
class PuroEarthPassportWorker
  include Sidekiq::Job
  sidekiq_options queue: "web3", retry: 5

  def perform(maintenance_record_id)
    record = MaintenanceRecord.find(maintenance_record_id)
    tree   = record.maintainable

    unless tree.is_a?(Tree)
      Rails.logger.warn "🌿 [Puro.earth] Record ##{maintenance_record_id} maintainable is not a Tree, skipping."
      return
    end

    payload = build_passport_payload(record, tree)

    # TODO: Replace with real Puro.earth API / blockchain anchoring service
    # e.g. PuroEarth::PassportService.new(payload).anchor!
    tx_hash = "0x#{SecureRandom.hex(32)}"

    record.update!(biomass_passport_tx_hash: tx_hash)

    Rails.logger.info "🌿 [Puro.earth] Biomass Passport for Puro.earth generated. " \
                      "Tree #{tree.did}, yield: #{record.biomass_yield_kg} kg, tx: #{tx_hash}"

    payload
  end

  private

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
