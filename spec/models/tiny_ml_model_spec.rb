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
  end
end
