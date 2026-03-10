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
      }.to raise_error(HardwareKeyService::RotationPendingError, /Ротація заблокована/)

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

  describe ".provision" do
    it "creates a HardwareKey and returns hex key" do
      result = described_class.provision(tree)

      expect(result).to be_a(String)
      expect(result.length).to eq(64) # 32 bytes = 64 hex chars
      expect(result).to match(/\A[0-9A-F]+\z/)

      hw_key = HardwareKey.find_by(device_uid: tree.did)
      expect(hw_key).to be_present
      expect(hw_key.aes_key_hex).to eq(result)
    end

    it "uses uid for gateway devices" do
      gateway = create(:gateway, cluster: cluster)

      result = described_class.provision(gateway)

      hw_key = HardwareKey.find_by(device_uid: gateway.uid)
      expect(hw_key).to be_present
      expect(hw_key.aes_key_hex).to eq(result)
    end
  end

  describe ".rotate" do
    let!(:hardware_key) do
      HardwareKey.create!(
        device_uid: tree.did,
        aes_key_hex: original_key,
        previous_aes_key_hex: nil
      )
    end

    it "finds device by DID (Tree) and calls rotate!" do
      new_key = described_class.rotate(tree.did)

      expect(new_key).to be_a(String)
      expect(new_key.length).to eq(64)

      hardware_key.reload
      expect(hardware_key.aes_key_hex).to eq(new_key)
      expect(hardware_key.previous_aes_key_hex).to eq(original_key)
    end

    it "finds device by UID (Gateway) and calls rotate!" do
      gateway = create(:gateway, cluster: cluster)
      gw_key_hex = SecureRandom.hex(32).upcase
      gw_hw_key = HardwareKey.create!(
        device_uid: gateway.uid,
        aes_key_hex: gw_key_hex,
        previous_aes_key_hex: nil
      )

      new_key = described_class.rotate(gateway.uid)

      gw_hw_key.reload
      expect(gw_hw_key.aes_key_hex).to eq(new_key)
      expect(gw_hw_key.previous_aes_key_hex).to eq(gw_key_hex)
    end

    it "raises when device not found" do
      expect {
        described_class.rotate("NONEXISTENT-DID")
      }.to raise_error(RuntimeError, /не знайдено/)
    end
  end
end
