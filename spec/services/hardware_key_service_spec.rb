# frozen_string_literal: true

require "rails_helper"

RSpec.describe HardwareKeyService, type: :service do
  let(:tree_family) { create(:tree_family) }
  let(:cluster) { create(:cluster) }
  let(:tree) { create(:tree, cluster: cluster, tree_family: tree_family) }
  let(:original_key) { SecureRandom.hex(32).upcase }

  before do
    # Configure ActiveRecord Encryption for tests
    ActiveRecord::Encryption.configure(
      primary_key: "test-primary-key-that-is-long-enough",
      deterministic_key: "test-deterministic-key-long-enough",
      key_derivation_salt: "test-salt-value-for-derivation-ok"
    )
    allow(ActuatorCommandWorker).to receive(:perform_async)
  end

  describe "#rotate!" do
    let!(:hardware_key) do
      HardwareKey.create!(
        device_uid: tree.did,
        aes_key_hex: original_key,
        previous_aes_key_hex: nil
      )
    end

    it "successfully rotates the key when no previous rotation is pending" do
      service = described_class.new(tree)
      new_key = service.rotate!

      hardware_key.reload
      expect(hardware_key.aes_key_hex).to eq(new_key)
      expect(hardware_key.previous_aes_key_hex).to eq(original_key)
      expect(hardware_key.rotated_at).not_to be_nil
    end

    it "raises error when previous rotation is still pending (dead-end protection)" do
      hardware_key.update!(previous_aes_key_hex: SecureRandom.hex(32).upcase)

      service = described_class.new(tree)
      expect {
        service.rotate!
      }.to raise_error(RuntimeError, /Ротація заблокована/)

      # Key should remain unchanged
      hardware_key.reload
      expect(hardware_key.aes_key_hex).to eq(original_key)
    end

    it "rolls back DB changes when downlink enqueue fails (atomicity)" do
      service = described_class.new(tree)

      # Stub trigger_key_update_downlink to raise, simulating Redis/Sidekiq failure
      allow(service).to receive(:trigger_key_update_downlink).and_raise(StandardError.new("Redis unavailable"))

      expect {
        service.rotate!
      }.to raise_error(StandardError, /Redis unavailable/)

      # Key should remain unchanged because transaction rolled back
      hardware_key.reload
      expect(hardware_key.aes_key_hex).to eq(original_key)
      expect(hardware_key.previous_aes_key_hex).to be_nil
    end

    it "allows rotation after grace period is cleared" do
      # First rotation
      service = described_class.new(tree)
      service.rotate!

      # Clear grace period (simulating device confirmation)
      hardware_key.reload
      hardware_key.clear_grace_period!

      # Second rotation should now succeed
      expect {
        service.rotate!
      }.not_to raise_error
    end
  end
end
