# frozen_string_literal: true

# [S6.17] Seed governance-aware system parameters for Dynamic Tax Rate
# and Insurance Pool Threshold. These values are synced from on-chain
# ProtocolParameters.sol via Governance::ParameterSyncWorker.
#
# Default values match the previously hardcoded constants in BlockchainMintingService.
class SeedGovernanceSystemParameters < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO system_parameters (key, value, value_type, category, source, min_value, max_value, created_at, updated_at)
      VALUES
        ('dynamic_tax_rate', '0.02', 'decimal', 'tokenomics', 'default', 0, 0.5, NOW(), NOW()),
        ('insurance_pool_threshold', '100000', 'integer', 'insurance', 'default', 0, NULL, NOW(), NOW())
      ON CONFLICT (key) DO NOTHING
    SQL
  end

  def down
    execute <<~SQL
      DELETE FROM system_parameters WHERE key IN ('dynamic_tax_rate', 'insurance_pool_threshold')
    SQL
  end
end
