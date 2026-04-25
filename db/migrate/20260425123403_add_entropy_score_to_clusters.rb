# Entropy Quality Monitor (Quantum Pre-Stress Detector).
#
# Adds denormalized entropy_score to clusters, analogous to health_index.
# Shannon entropy of z_value distributions across a cluster's trees serves as
# an early warning indicator: a healthy forest has diverse chaotic z_values
# (high entropy ≈ 1.0), while forest-wide stress homogenizes readings
# (low entropy → pre-stress signal).
#
# NOTE: hrng_seed (chaos_seed from firmware HRNG) is NOT added to telemetry_logs
# because it is not transmitted in the 21-byte LoRa packet (see 03_01 Phase 2).
# The backend uses z_value (Lorenz attractor output) as the entropy proxy.
# See: docs/04_02, ЧДТУ task #12 (08_04).
class AddEntropyScoreToClusters < ActiveRecord::Migration[8.1]
  def change
    add_column :clusters, :entropy_score, :float
  end
end
