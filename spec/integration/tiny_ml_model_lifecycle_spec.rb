# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TinyML model lifecycle and drift tracking" do
  let(:tree_family) { create(:tree_family) }

  # ---------------------------------------------------------------------------
  # Versioning and validation
  # ---------------------------------------------------------------------------
  describe "version and format validation" do
    it "validates version uniqueness" do
      create(:tiny_ml_model, version: "v1.0.0")
      dup = build(:tiny_ml_model, version: "v1.0.0")
      expect(dup).not_to be_valid
    end

    it "validates model_format inclusion" do
      model = build(:tiny_ml_model, model_format: "invalid_format")
      expect(model).not_to be_valid
    end

    it "accepts all valid formats" do
      %w[tflite edge_impulse onnx c_array].each do |fmt|
        model = build(:tiny_ml_model, version: "v#{fmt}.0.0", model_format: fmt)
        expect(model).to be_valid
      end
    end

    it "validates min_firmware_version format" do
      model = build(:tiny_ml_model, min_firmware_version: "not_semver")
      expect(model).not_to be_valid

      model.min_firmware_version = "v2.1.0"
      expect(model).to be_valid
    end

    it "validates rollout_percentage range" do
      model = build(:tiny_ml_model, rollout_percentage: -1)
      expect(model).not_to be_valid

      model.rollout_percentage = 101
      expect(model).not_to be_valid

      model.rollout_percentage = 50
      expect(model).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # BigDecimal precision fields
  # ---------------------------------------------------------------------------
  describe "accuracy_score and threshold (BigDecimal bridge)" do
    let(:model) { create(:tiny_ml_model) }

    it "stores and retrieves accuracy_score as BigDecimal" do
      model.accuracy_score = 0.95
      model.save!
      model.reload

      expect(model.accuracy_score).to eq(BigDecimal("0.95"))
    end

    it "stores and retrieves threshold as BigDecimal" do
      model.threshold = 0.7
      model.save!
      model.reload

      expect(model.threshold).to eq(BigDecimal("0.7"))
    end

    it "rejects accuracy_score outside 0..1 range" do
      model.accuracy_score = 1.5
      expect(model).not_to be_valid

      model.accuracy_score = -0.1
      expect(model).not_to be_valid
    end

    it "rejects non-numeric accuracy_score" do
      model.metadata = (model.metadata || {}).merge("accuracy_score" => "not_a_number")
      expect(model).not_to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Drift tracking
  # ---------------------------------------------------------------------------
  describe "drift tracking" do
    let(:model) { create(:tiny_ml_model) }

    it "records confirmed predictions and updates TPR" do
      model.record_prediction!(confirmed: true)
      expect(model.true_positive_rate).to eq(1.0)
      expect(model.false_positive_rate).to eq(0.0)
      expect(model.total_predictions).to eq(1)
    end

    it "tracks false positives" do
      model.record_prediction!(confirmed: true)
      model.record_prediction!(confirmed: false)

      expect(model.true_positive_rate).to eq(0.5)
      expect(model.false_positive_rate).to eq(0.5)
    end

    it "detects drifting model" do
      # Simulate many false positives
      model.update_columns(
        total_predictions: 100,
        confirmed_predictions: 80,
        false_positive_rate: 0.2,
        true_positive_rate: 0.8
      )

      expect(model.drifting?).to be true
    end

    it "non-drifting model returns false" do
      model.update_columns(false_positive_rate: 0.05)
      expect(model.drifting?).to be false
    end

    it "scopes drifting models" do
      drifting = create(:tiny_ml_model, version: "vD.0.0")
      drifting.update_columns(false_positive_rate: 0.2)

      stable = create(:tiny_ml_model, version: "vS.0.0")
      stable.update_columns(false_positive_rate: 0.05)

      expect(TinyMlModel.drifting).to include(drifting)
      expect(TinyMlModel.drifting).not_to include(stable)
    end
  end

  # ---------------------------------------------------------------------------
  # Binary bridge & OTA chunking
  # ---------------------------------------------------------------------------
  describe "binary payload and chunking" do
    let(:model) { create(:tiny_ml_model, binary_weights_payload: "x" * 1500) }

    it "returns correct payload_size" do
      expect(model.payload_size).to eq(1500)
    end

    it "chunks payload into 512-byte segments" do
      chunks = model.chunks(512)
      expect(chunks.length).to eq(3) # 1500 / 512 = 2.93 → 3 chunks
      expect(chunks.first.bytesize).to eq(512)
      expect(chunks.last.bytesize).to eq(1500 - 512 * 2)
    end

    it "returns total_chunks count" do
      expect(model.total_chunks(512)).to eq(3)
    end

    it "handles empty payload" do
      model.update_columns(binary_weights_payload: nil)
      expect(model.payload_size).to eq(0)
      expect(model.chunks).to eq([])
      expect(model.total_chunks).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # Firmware compatibility
  # ---------------------------------------------------------------------------
  describe "firmware compatibility" do
    let(:model) { create(:tiny_ml_model, min_firmware_version: "v2.1.0") }

    it "returns compatible for higher firmware" do
      expect(model.firmware_compatible?("v3.0.0")).to be true
    end

    it "returns compatible for exact match" do
      expect(model.firmware_compatible?("v2.1.0")).to be true
    end

    it "returns incompatible for lower firmware" do
      expect(model.firmware_compatible?("v1.9.0")).to be false
    end

    it "returns compatible when min version not set" do
      model.update!(min_firmware_version: nil)
      expect(model.firmware_compatible?("v1.0.0")).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Phased rollout activation
  # ---------------------------------------------------------------------------
  describe "phased rollout" do
    let!(:old_model) { create(:tiny_ml_model, :active, version: "v1.0.0", tree_family: tree_family) }
    let!(:new_model) { create(:tiny_ml_model, version: "v2.0.0", tree_family: tree_family) }

    it "activates new model and deactivates old ones for same family" do
      new_model.activate!(percentage: 10)

      new_model.reload
      old_model.reload

      expect(new_model.is_active).to be true
      expect(new_model.rollout_percentage).to eq(10)
      expect(old_model.is_active).to be false
    end

    it "clamps percentage to 1-100" do
      new_model.activate!(percentage: 0)
      expect(new_model.reload.rollout_percentage).to eq(1)

      new_model.activate!(percentage: 200)
      expect(new_model.reload.rollout_percentage).to eq(100)
    end
  end

  # ---------------------------------------------------------------------------
  # Checksum generation
  # ---------------------------------------------------------------------------
  describe "checksum generation" do
    it "generates SHA256 checksum on save" do
      model = create(:tiny_ml_model, binary_weights_payload: "test_data")
      expect(model.checksum).to eq(Digest::SHA256.hexdigest("test_data"))
    end

    it "updates checksum when payload changes" do
      model = create(:tiny_ml_model, binary_weights_payload: "data_v1")
      old_checksum = model.checksum

      model.update!(binary_weights_payload: "data_v2")
      expect(model.checksum).not_to eq(old_checksum)
    end
  end
end
