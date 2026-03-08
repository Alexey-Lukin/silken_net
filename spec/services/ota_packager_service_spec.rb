# frozen_string_literal: true

require "rails_helper"

RSpec.describe OtaPackagerService do
  let(:firmware) do
    instance_double(BioContractFirmware, version: "1.0.0", binary_payload: payload, binary_sha256: "abc123")
  end

  describe ".prepare" do
    let(:payload) { "\xAA\xBB\xCC" }

    it "returns manifest and packages" do
      result = described_class.prepare(firmware)

      expect(result).to have_key(:manifest)
      expect(result).to have_key(:packages)
    end

    it "manifest contains correct metadata" do
      result = described_class.prepare(firmware)
      manifest = result[:manifest]

      expect(manifest[:version]).to eq("1.0.0")
      expect(manifest[:total_size]).to eq(3)
      expect(manifest[:checksum]).to be_a(String)
      expect(manifest[:sha256]).to eq("abc123")
      expect(manifest[:total_chunks]).to eq(1)
    end
  end

  describe "generate_packages" do
    context "with small payload (single chunk)" do
      let(:payload) { "\xAA\xBB\xCC" }

      it "returns an Enumerator for lazy evaluation" do
        result = described_class.prepare(firmware)

        expect(result[:packages]).to be_a(Enumerator)
      end

      it "produces exactly one package" do
        packages = described_class.prepare(firmware)[:packages].to_a

        expect(packages.size).to eq(1)
      end

      it "package has 5-byte header (marker + 16-bit index + 16-bit total)" do
        package = described_class.prepare(firmware)[:packages].first
        marker, index, total = package[0..4].unpack("Cnn")

        expect(marker).to eq(0x99)
        expect(index).to eq(0)
        expect(total).to eq(1)
      end

      it "appends 2-byte CRC16 at the end" do
        package = described_class.prepare(firmware)[:packages].first

        # 5 header + 3 data + 2 CRC = 10
        expect(package.bytesize).to eq(10)
      end

      it "CRC16 validates package integrity" do
        package = described_class.prepare(firmware)[:packages].first
        payload_without_crc = package[0..-3]
        crc_in_packet = package[-2..].unpack1("n")

        # Recalculate CRC
        svc = described_class.new(firmware, 512)
        expected_crc = svc.send(:crc16_ccitt, payload_without_crc)

        expect(crc_in_packet).to eq(expected_crc)
      end
    end

    context "with payload exceeding 255 chunks (16-bit overflow protection)" do
      # 256KB payload with 512-byte chunks = 512 chunks (exceeds uint8 max of 255)
      let(:payload) { "\xFF" * (256 * 1024) }

      it "correctly encodes chunk index > 255" do
        packages = described_class.prepare(firmware)[:packages]
        chunk_300 = packages.drop(300).first
        _, index, total = chunk_300[0..4].unpack("Cnn")

        expect(index).to eq(300)
        expect(total).to eq(512)
      end

      it "correctly encodes total > 255" do
        package = described_class.prepare(firmware)[:packages].first
        _, _, total = package[0..4].unpack("Cnn")

        expect(total).to eq(512)
      end

      it "manifest total_chunks matches actual package count" do
        result = described_class.prepare(firmware)
        actual_count = result[:packages].count

        expect(actual_count).to eq(result[:manifest][:total_chunks])
      end
    end

    context "with multi-chunk payload" do
      # 1025 bytes at 512 chunk size = 3 chunks (512 + 512 + 1)
      let(:payload) { "\xAB" * 1025 }

      it "splits payload into correct number of chunks" do
        result = described_class.prepare(firmware, chunk_size: 512)
        packages = result[:packages].to_a

        expect(packages.size).to eq(3)
        expect(result[:manifest][:total_chunks]).to eq(3)
      end

      it "last chunk contains remaining bytes" do
        packages = described_class.prepare(firmware, chunk_size: 512)[:packages].to_a
        last_package = packages.last

        # 5 header + 1 byte remaining + 2 CRC = 8
        expect(last_package.bytesize).to eq(8)
      end
    end

    context "when CRC16 detects corruption" do
      let(:payload) { "\xDE\xAD\xBE\xEF" * 128 }

      it "CRC changes when data is altered" do
        package = described_class.prepare(firmware)[:packages].first
        original_crc = package[-2..].unpack1("n")

        # Corrupt one data byte
        corrupted = package.dup
        corrupted.setbyte(6, corrupted.getbyte(6) ^ 0xFF)
        corrupted_payload = corrupted[0..-3]

        svc = described_class.new(firmware, 512)
        recalculated_crc = svc.send(:crc16_ccitt, corrupted_payload)

        expect(recalculated_crc).not_to eq(original_crc)
      end
    end
  end
end
