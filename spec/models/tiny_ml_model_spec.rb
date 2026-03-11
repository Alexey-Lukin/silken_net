# frozen_string_literal: true

require "rails_helper"

RSpec.describe TinyMlModel, type: :model do
  # =========================================================================
  # VALIDATIONS
  # =========================================================================
  describe "validations" do
    it "is valid with factory defaults" do
      expect(build(:tiny_ml_model)).to be_valid
    end

    it "requires version" do
      expect(build(:tiny_ml_model, version: nil)).not_to be_valid
    end

    it "enforces version uniqueness" do
      create(:tiny_ml_model, version: "v1.0.0")
      duplicate = build(:tiny_ml_model, version: "v1.0.0")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:version]).to be_present
    end

    it "requires binary_weights_payload" do
      expect(build(:tiny_ml_model, binary_weights_payload: nil)).not_to be_valid
    end

    it "rejects payload exceeding 256 KB" do
      oversized = build(:tiny_ml_model, binary_weights_payload: "x" * (256.kilobytes + 1))
      expect(oversized).not_to be_valid
      expect(oversized.errors[:binary_weights_payload]).to be_present
    end

    it "accepts payload at exactly 256 KB" do
      exact = build(:tiny_ml_model, binary_weights_payload: "x" * 256.kilobytes)
      expect(exact).to be_valid
    end

    # --- model_format ---
    describe "model_format" do
      %w[tflite edge_impulse onnx c_array].each do |fmt|
        it "accepts '#{fmt}'" do
          expect(build(:tiny_ml_model, model_format: fmt)).to be_valid
        end
      end

      it "rejects an unsupported format" do
        model = build(:tiny_ml_model, model_format: "pytorch")
        expect(model).not_to be_valid
        expect(model.errors[:model_format]).to be_present
      end

      it "allows nil (legacy models without format)" do
        expect(build(:tiny_ml_model, model_format: nil)).to be_valid
      end
    end

    # --- min_firmware_version ---
    describe "min_firmware_version" do
      it "accepts valid semver with v-prefix" do
        expect(build(:tiny_ml_model, min_firmware_version: "v2.1.0")).to be_valid
      end

      it "accepts valid semver without v-prefix" do
        expect(build(:tiny_ml_model, min_firmware_version: "2.1.0")).to be_valid
      end

      it "accepts semver with suffix (e.g. v2.1.0-silken)" do
        expect(build(:tiny_ml_model, min_firmware_version: "v2.1.0-silken")).to be_valid
      end

      it "rejects malformed version string" do
        model = build(:tiny_ml_model, min_firmware_version: "latest")
        expect(model).not_to be_valid
        expect(model.errors[:min_firmware_version]).to be_present
      end

      it "allows nil" do
        expect(build(:tiny_ml_model, min_firmware_version: nil)).to be_valid
      end
    end

    # --- rollout_percentage ---
    describe "rollout_percentage" do
      it "defaults to 0" do
        model = build(:tiny_ml_model)
        expect(model.rollout_percentage).to eq(0)
      end

      it "accepts 0" do
        expect(build(:tiny_ml_model, rollout_percentage: 0)).to be_valid
      end

      it "accepts 100" do
        expect(build(:tiny_ml_model, rollout_percentage: 100)).to be_valid
      end

      it "rejects values above 100" do
        model = build(:tiny_ml_model, rollout_percentage: 101)
        expect(model).not_to be_valid
        expect(model.errors[:rollout_percentage]).to be_present
      end

      it "rejects negative values" do
        model = build(:tiny_ml_model, rollout_percentage: -1)
        expect(model).not_to be_valid
        expect(model.errors[:rollout_percentage]).to be_present
      end

      it "rejects non-integer values" do
        model = build(:tiny_ml_model, rollout_percentage: 50.5)
        expect(model).not_to be_valid
      end
    end

    # --- accuracy_score / threshold (BigDecimal validation) ---
    describe "accuracy_score and threshold" do
      it "rejects accuracy_score > 1" do
        model = build(:tiny_ml_model)
        model.accuracy_score = "1.5"
        expect(model).not_to be_valid
        expect(model.errors[:accuracy_score]).to be_present
      end

      it "rejects negative accuracy_score" do
        model = build(:tiny_ml_model)
        model.accuracy_score = "-0.1"
        expect(model).not_to be_valid
        expect(model.errors[:accuracy_score]).to be_present
      end

      it "accepts accuracy_score in range 0..1" do
        model = build(:tiny_ml_model)
        model.accuracy_score = "0.95"
        model.threshold = "0.85"
        expect(model).to be_valid
      end

      it "rejects threshold > 1" do
        model = build(:tiny_ml_model)
        model.threshold = "1.01"
        expect(model).not_to be_valid
        expect(model.errors[:threshold]).to be_present
      end

      it "allows nil accuracy_score and threshold" do
        model = build(:tiny_ml_model)
        model.accuracy_score = nil
        model.threshold = nil
        expect(model).to be_valid
      end

      it "rejects non-numeric accuracy_score" do
        model = build(:tiny_ml_model)
        model.accuracy_score = "high"
        expect(model).not_to be_valid
        expect(model.errors[:accuracy_score]).to be_present
      end
    end
  end

  # =========================================================================
  # SCOPES
  # =========================================================================
  describe "scopes" do
    describe ".active" do
      it "returns only models with is_active = true" do
        active   = create(:tiny_ml_model, :active)
        inactive = create(:tiny_ml_model, is_active: false)

        expect(described_class.active).to include(active)
        expect(described_class.active).not_to include(inactive)
      end
    end

    describe ".latest" do
      it "orders by version descending" do
        v1 = create(:tiny_ml_model, version: "v1.0.0")
        v2 = create(:tiny_ml_model, version: "v2.0.0")
        v3 = create(:tiny_ml_model, version: "v3.0.0")

        expect(described_class.latest.first).to eq(v3)
        expect(described_class.latest.last).to eq(v1)
      end
    end
  end

  # =========================================================================
  # CALLBACKS
  # =========================================================================
  describe "#generate_checksum (before_save)" do
    it "computes SHA256 checksum when payload is set" do
      model = create(:tiny_ml_model, binary_weights_payload: "hello_world")
      expected = Digest::SHA256.hexdigest("hello_world")
      expect(model.checksum).to eq(expected)
    end

    it "updates checksum when payload changes" do
      model = create(:tiny_ml_model, binary_weights_payload: "original")
      model.update!(binary_weights_payload: "updated")
      expect(model.checksum).to eq(Digest::SHA256.hexdigest("updated"))
    end

    it "does not recompute checksum when other attributes change" do
      model           = create(:tiny_ml_model)
      original_checksum = model.checksum

      model.update!(version: "v99.9.9")

      expect(model.checksum).to eq(original_checksum)
    end
  end

  # =========================================================================
  # BIGDECIMAL ACCESSORS
  # =========================================================================
  describe "BigDecimal accessors" do
    describe "#accuracy_score" do
      it "returns BigDecimal" do
        model = build(:tiny_ml_model)
        model.accuracy_score = 0.95
        expect(model.accuracy_score).to be_a(BigDecimal)
      end

      it "preserves precision" do
        model = build(:tiny_ml_model)
        model.accuracy_score = "0.123456789"
        expect(model.accuracy_score).to eq(BigDecimal("0.123456789"))
      end

      it "returns nil when not set" do
        model = build(:tiny_ml_model)
        expect(model.accuracy_score).to be_nil
      end
    end

    describe "#threshold" do
      it "returns BigDecimal" do
        model = build(:tiny_ml_model)
        model.threshold = 0.85
        expect(model.threshold).to be_a(BigDecimal)
      end

      it "enables precise comparison for EwsAlert trigger" do
        model = build(:tiny_ml_model)
        model.threshold = "0.85"

        anomaly_probability = BigDecimal("0.850000000000001")
        expect(anomaly_probability > model.threshold).to be true
      end

      it "returns nil when not set" do
        model = build(:tiny_ml_model)
        expect(model.threshold).to be_nil
      end
    end

    it "persists BigDecimal values through save cycle" do
      model = create(:tiny_ml_model)
      model.update!(metadata: (model.metadata || {}).merge("accuracy_score" => "0.95", "threshold" => "0.85"))
      model.reload

      expect(model.accuracy_score).to eq(BigDecimal("0.95"))
      expect(model.threshold).to eq(BigDecimal("0.85"))
    end
  end

  # =========================================================================
  # INSTANCE METHODS
  # =========================================================================
  describe "#binary_payload" do
    it "returns the binary_weights_payload" do
      payload = SecureRandom.random_bytes(512)
      model   = build(:tiny_ml_model, binary_weights_payload: payload)
      expect(model.binary_payload).to eq(payload)
    end
  end

  describe "#payload_size" do
    it "returns 0 when payload is nil" do
      model = build(:tiny_ml_model)
      allow(model).to receive(:binary_payload).and_return(nil)
      expect(model.payload_size).to eq(0)
    end

    it "returns the byte size of the payload" do
      payload = "x" * 1024
      model   = build(:tiny_ml_model, binary_weights_payload: payload)
      expect(model.payload_size).to eq(1024)
    end
  end

  describe "#chunks" do
    it "returns an empty array when payload is empty" do
      model = build(:tiny_ml_model)
      allow(model).to receive(:payload_size).and_return(0)
      expect(model.chunks).to eq([])
    end

    it "splits payload into 512-byte chunks by default" do
      payload = "A" * 1536   # exactly 3 chunks of 512
      model   = build(:tiny_ml_model, binary_weights_payload: payload)
      expect(model.chunks.size).to eq(3)
      expect(model.chunks.first.bytesize).to eq(512)
    end

    it "last chunk contains remainder bytes" do
      payload = "B" * 600     # 1 full chunk (512) + 1 partial (88)
      model   = build(:tiny_ml_model, binary_weights_payload: payload)
      chunks  = model.chunks
      expect(chunks.size).to eq(2)
      expect(chunks.last.bytesize).to eq(88)
    end

    it "accepts a custom chunk_size" do
      payload = "C" * 100
      model   = build(:tiny_ml_model, binary_weights_payload: payload)
      expect(model.chunks(10).size).to eq(10)
    end
  end

  describe "#total_chunks" do
    it "returns 0 when payload is empty" do
      model = build(:tiny_ml_model)
      allow(model).to receive(:payload_size).and_return(0)
      expect(model.total_chunks).to eq(0)
    end

    it "returns the ceiling of payload_size / chunk_size" do
      payload = "D" * 1025    # 1025 / 512 = 2.002 → ceil = 3
      model   = build(:tiny_ml_model, binary_weights_payload: payload)
      expect(model.total_chunks).to eq(3)
    end

    it "matches the actual number of chunks returned" do
      payload = SecureRandom.random_bytes(2000)
      model   = build(:tiny_ml_model, binary_weights_payload: payload)
      expect(model.total_chunks).to eq(model.chunks.size)
    end
  end

  # =========================================================================
  # FIRMWARE COMPATIBILITY
  # =========================================================================
  describe "#firmware_compatible?" do
    it "returns true when min_firmware_version is nil" do
      model = build(:tiny_ml_model, min_firmware_version: nil)
      expect(model.firmware_compatible?("v1.0.0")).to be true
    end

    it "returns true when firmware version matches exactly" do
      model = build(:tiny_ml_model, min_firmware_version: "v2.1.0")
      expect(model.firmware_compatible?("v2.1.0")).to be true
    end

    it "returns true when firmware version is newer" do
      model = build(:tiny_ml_model, min_firmware_version: "v2.1.0")
      expect(model.firmware_compatible?("v3.0.0")).to be true
    end

    it "returns false when firmware version is older" do
      model = build(:tiny_ml_model, min_firmware_version: "v2.1.0")
      expect(model.firmware_compatible?("v1.5.0")).to be false
    end

    it "handles versions with suffixes (e.g. v2.1.0-silken)" do
      model = build(:tiny_ml_model, min_firmware_version: "v2.1.0")
      expect(model.firmware_compatible?("v2.1.0-silken")).to be true
    end
  end

  # =========================================================================
  # ACTIVATE! (with Phased Diffusion)
  # =========================================================================
  describe "#activate!" do
    it "sets is_active to true for this model" do
      model = create(:tiny_ml_model)
      model.activate!
      expect(model.reload.is_active).to be true
    end

    it "deactivates other models for the same tree_family" do
      family  = create(:tree_family)
      old     = create(:tiny_ml_model, :active, :for_family, tree_family: family)
      new_model = create(:tiny_ml_model, :for_family, tree_family: family)

      new_model.activate!

      expect(old.reload.is_active).to be false
      expect(new_model.reload.is_active).to be true
    end

    it "does not deactivate models from a different tree_family" do
      family_a = create(:tree_family)
      family_b = create(:tree_family)
      model_a  = create(:tiny_ml_model, :active, :for_family, tree_family: family_a)
      model_b  = create(:tiny_ml_model, :for_family, tree_family: family_b)

      model_b.activate!

      expect(model_a.reload.is_active).to be true
    end

    it "handles the case where tree_family_id is nil (global models do not conflict)" do
      m1 = create(:tiny_ml_model, :active, tree_family: nil)
      m2 = create(:tiny_ml_model, tree_family: nil)

      m2.activate!

      # Both nil-family models are treated as the same group in the query
      expect(m1.reload.is_active).to be false
      expect(m2.reload.is_active).to be true
    end

    it "defaults rollout_percentage to 100" do
      model = create(:tiny_ml_model)
      model.activate!
      expect(model.reload.rollout_percentage).to eq(100)
    end

    it "accepts custom rollout_percentage for phased diffusion" do
      model = create(:tiny_ml_model)
      model.activate!(percentage: 10)
      expect(model.reload.rollout_percentage).to eq(10)
      expect(model.reload.is_active).to be true
    end

    it "clamps rollout_percentage to 1..100 range" do
      model = create(:tiny_ml_model)
      model.activate!(percentage: 0)
      expect(model.reload.rollout_percentage).to eq(1)
    end
  end

  # =========================================================================
  # DRIFT TRACKING (Feedback Loop)
  # =========================================================================
  describe "drift tracking" do
    describe "#record_prediction!" do
      it "increments total_predictions and confirmed for true positive" do
        model = create(:tiny_ml_model)
        model.record_prediction!(confirmed: true)

        model.reload
        expect(model.total_predictions).to eq(1)
        expect(model.confirmed_predictions).to eq(1)
        expect(model.true_positive_rate).to eq(1.0)
        expect(model.false_positive_rate).to eq(0.0)
      end

      it "increments only total_predictions for false positive" do
        model = create(:tiny_ml_model)
        model.record_prediction!(confirmed: false)

        model.reload
        expect(model.total_predictions).to eq(1)
        expect(model.confirmed_predictions).to eq(0)
        expect(model.false_positive_rate).to eq(1.0)
      end

      it "updates drift_checked_at" do
        model = create(:tiny_ml_model)
        expect(model.drift_checked_at).to be_nil

        model.record_prediction!(confirmed: true)
        expect(model.reload.drift_checked_at).to be_present
      end
    end

    describe "#drifting?" do
      it "returns true when FPR exceeds threshold" do
        model = create(:tiny_ml_model, false_positive_rate: 0.20)
        expect(model.drifting?).to be true
      end

      it "returns false when FPR is below threshold" do
        model = create(:tiny_ml_model, false_positive_rate: 0.05)
        expect(model.drifting?).to be false
      end

      it "returns false when FPR is nil" do
        model = create(:tiny_ml_model, false_positive_rate: nil)
        expect(model.drifting?).to be false
      end
    end

    describe ".drifting scope" do
      it "returns models with high false positive rate" do
        drifting = create(:tiny_ml_model, false_positive_rate: 0.25)
        stable = create(:tiny_ml_model, false_positive_rate: 0.05)

        expect(described_class.drifting).to include(drifting)
        expect(described_class.drifting).not_to include(stable)
      end
    end

    describe "#recalculate_drift_metrics!" do
      it "returns early when total_predictions is zero" do
        model = create(:tiny_ml_model, total_predictions: 0)
        model.recalculate_drift_metrics!

        expect(model.true_positive_rate).to be_nil
        expect(model.false_positive_rate).to be_nil
      end
    end
  end
end
