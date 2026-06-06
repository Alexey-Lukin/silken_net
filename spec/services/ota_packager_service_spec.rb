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

      it "package has 7-byte header (marker + index + total + explicit len, all 16-bit BE)" do
        # [FIX AUDIT-2026-06-06] len-поле додано: Queen більше не вгадує довжину
        # з CBC zero-padding (стара формула обрізала 1..16 байт кожного чанка).
        package = described_class.prepare(firmware)[:packages].first
        marker, index, total, len = package[0..6].unpack("Cnnn")

        expect(marker).to eq(0x99)
        expect(index).to eq(0)
        expect(total).to eq(1)
        # wire = payload(3) + zero-pad(4) + CRC32(4) = 11 (LoRa-MTU aligned)
        expect(len).to eq(11)
      end

      it "appends 2-byte CRC16 at the end" do
        package = described_class.prepare(firmware)[:packages].first

        # 7 header + 11 wire data + 2 CRC = 20
        expect(package.bytesize).to eq(20)
      end

      it "CRC16 validates package integrity" do
        package = described_class.prepare(firmware)[:packages].first
        payload_without_crc = package[0..-3]
        crc_in_packet = package[-2..].unpack1("n")

        # Recalculate CRC
        svc = described_class.new(firmware, 512)
        expected_crc = svc.class.crc16_ccitt(payload_without_crc)

        expect(crc_in_packet).to eq(expected_crc)
      end
    end

    context "with payload exceeding 255 chunks (16-bit overflow protection)" do
      # 256KB payload + LoRa pad/CRC32 wire-trailer → 513 CoAP chunks of 512
      let(:payload) { "\xFF" * (256 * 1024) }

      it "correctly encodes chunk index > 255" do
        packages = described_class.prepare(firmware)[:packages]
        chunk_300 = packages.drop(300).first
        _, index, total = chunk_300[0..4].unpack("Cnn")

        expect(index).to eq(300)
        expect(total).to eq(513)
      end

      it "correctly encodes total > 255" do
        package = described_class.prepare(firmware)[:packages].first
        _, _, total = package[0..4].unpack("Cnn")

        expect(total).to eq(513)
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

      it "last chunk contains remaining wire bytes" do
        packages = described_class.prepare(firmware, chunk_size: 512)[:packages].to_a
        last_package = packages.last

        # wire = 1025 + pad(5) + CRC32(4) = 1034 → 512 + 512 + 10;
        # last: 7 header + 10 wire + 2 CRC = 19
        expect(last_package.bytesize).to eq(19)
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
        recalculated_crc = svc.class.crc16_ccitt(corrupted_payload)

        expect(recalculated_crc).not_to eq(original_crc)
      end
    end

    context "with LoRa MTU (11-byte chunks)" do
      let(:payload) { "\xAA" * 33 } # wire = 33 + pad(7) + CRC32(4) = 44 → 4 chunks

      it "produces correct number of chunks for LoRa" do
        result = described_class.prepare(firmware, chunk_size: described_class::LORA_MTU)
        packages = result[:packages].to_a

        expect(packages.size).to eq(4)
        expect(result[:manifest][:total_chunks]).to eq(4)
      end

      it "each LoRa chunk has correct header with 0x99 marker" do
        packages = described_class.prepare(firmware, chunk_size: described_class::LORA_MTU)[:packages].to_a
        packages.each_with_index do |pkg, i|
          marker, index, total = pkg[0..4].unpack("Cnn")
          expect(marker).to eq(0x99)
          expect(index).to eq(i)
          expect(total).to eq(4)
        end
      end
    end

    context "with single-byte payload" do
      let(:payload) { "\xFF" }

      it "produces exactly one package" do
        packages = described_class.prepare(firmware)[:packages].to_a
        expect(packages.size).to eq(1)
      end

      it "package contains 7 header + 11 wire bytes + 2 CRC = 20 bytes" do
        # wire = 1 + pad(6) + CRC32(4) = 11
        package = described_class.prepare(firmware)[:packages].first
        expect(package.bytesize).to eq(20)
      end
    end

    context "with exact block-size payload (512 bytes)" do
      let(:payload) { "\xBB" * 512 }

      it "splits wire stream (payload + pad + CRC32) into two chunks" do
        # wire = 512 + pad(1) + CRC32(4) = 517 → 512 + 5
        result = described_class.prepare(firmware, chunk_size: 512)
        packages = result[:packages].to_a
        expect(packages.size).to eq(2)
        expect(result[:manifest][:total_chunks]).to eq(2)
      end

      it "first chunk carries a FULL 512-byte data section with explicit len" do
        # [FIX AUDIT-2026-06-06] Регресія старого бага: повний чанк мусить
        # нести рівно 512 байт і чесний len — Queen раніше обрізала його до 500.
        package = described_class.prepare(firmware, chunk_size: 512)[:packages].first
        len = package[5..6].unpack1("n")
        expect(len).to eq(512)
        # 7 header + 512 data + 2 CRC = 521
        expect(package.bytesize).to eq(521)
      end
    end

    # [FIX AUDIT-2026-06-06] Wire-потік LoRa-шару: Soldier рахує отримане як
    # 11 × chunks, тож CRC32 мусить лягати РІВНО в кінець останнього 11-байт
    # чанка. Інваріанти нижче — крос-шаровий контракт із firmware
    # (test_soldier_logic.c OTA_Verify_CRC + queen broadcast math).
    describe "wire payload invariants (LoRa CRC32 trailer)" do
      [ 1, 3, 7, 11, 33, 512, 1025 ].each do |size|
        context "with #{size}-byte payload" do
          let(:payload) { "\xC3".b * size }

          it "reassembled wire stream is LoRa-MTU aligned and CRC32-terminated" do
            packages = described_class.prepare(firmware, chunk_size: 512)[:packages].to_a

            wire = packages.map { |pkg|
              len = pkg[5..6].unpack1("n")
              pkg[7, len]
            }.join.b

            expect(wire.bytesize % described_class::LORA_MTU).to eq(0)

            data = wire[0..-5]
            crc  = wire[-4..].unpack1("N")
            expect(crc).to eq(Zlib.crc32(data))

            # Оригінальний bytecode лежить префіксом; pad — нулі
            expect(data[0, size]).to eq(payload)
            expect(data[size..]).to match(/\A\x00*\z/n)
          end
        end
      end
    end

    context "when manifest format is validated" do
      let(:payload) { "\xAA\xBB\xCC\xDD" }

      it "checksum is uppercase hexadecimal CRC32" do
        result = described_class.prepare(firmware)
        expect(result[:manifest][:checksum]).to match(/\A[0-9A-F]+\z/)
      end

      it "checksum matches Zlib.crc32 of payload" do
        result = described_class.prepare(firmware)
        expected = Zlib.crc32(payload).to_s(16).upcase
        expect(result[:manifest][:checksum]).to eq(expected)
      end

      it "sha256 comes from firmware object" do
        result = described_class.prepare(firmware)
        expect(result[:manifest][:sha256]).to eq("abc123")
      end
    end

    context "when CRC16-CCITT produces known values" do
      let(:payload) { "\xAA\xBB\xCC" }

      it "produces correct CRC for known input" do
        svc = described_class.new(firmware, 512)
        # CRC16-CCITT of empty string should be 0xFFFF (initial value)
        crc = svc.class.crc16_ccitt("")
        expect(crc).to eq(0xFFFF)
      end

      it "produces non-zero CRC for non-empty input" do
        svc = described_class.new(firmware, 512)
        crc = svc.class.crc16_ccitt("123456789")
        expect(crc).to be_a(Integer)
        expect(crc).to be > 0
        expect(crc).to be <= 0xFFFF
      end
    end

    context "when packages return lazy Enumerator" do
      let(:payload) { "\xAA" * 10_000 }

      it "returns Enumerator that generates packages on demand" do
        result = described_class.prepare(firmware, chunk_size: 512)
        packages = result[:packages]

        expect(packages).to be_a(Enumerator)
        first_package = packages.first
        expect(first_package).to be_a(String)
      end
    end
  end

  # =========================================================================
  # [FW.23] OTA HMAC-SHA256 dual-gate authentication
  # =========================================================================
  describe "HMAC trailer (FW.23)" do
    let(:hmac_firmware) do
      instance_double(BioContractFirmware,
                       id: 42,
                       version: "1.0.0",
                       binary_payload: payload,
                       binary_sha256: "abc123")
    end
    let(:cluster_id) { "cluster-test-1" }

    describe ".compute_hmac_tag" do
      let(:payload) { "RITE\x03\x00\x00\x00\xAA\xBB\xCC".b }

      it "returns 32-byte binary digest" do
        tag = described_class.compute_hmac_tag(payload, 42, 5, cluster_id: cluster_id)
        expect(tag.bytesize).to eq(32)
        expect(tag.encoding).to eq(Encoding::ASCII_8BIT)
      end

      it "is deterministic for fixed (bytecode, version_id, total, cluster_id)" do
        tag1 = described_class.compute_hmac_tag(payload, 42, 5, cluster_id: cluster_id)
        tag2 = described_class.compute_hmac_tag(payload, 42, 5, cluster_id: cluster_id)
        expect(tag1).to eq(tag2)
      end

      it "anti-replay: changing version_id changes tag" do
        tag1 = described_class.compute_hmac_tag(payload, 42, 5, cluster_id: cluster_id)
        tag2 = described_class.compute_hmac_tag(payload, 43, 5, cluster_id: cluster_id)
        expect(tag1).not_to eq(tag2)
      end

      it "anti-truncation: changing total_chunks changes tag" do
        tag1 = described_class.compute_hmac_tag(payload, 42, 5, cluster_id: cluster_id)
        tag2 = described_class.compute_hmac_tag(payload, 42, 4, cluster_id: cluster_id)
        expect(tag1).not_to eq(tag2)
      end

      it "differs across cluster_ids (per-cluster K_ota isolation)" do
        tag_a = described_class.compute_hmac_tag(payload, 42, 5, cluster_id: "cluster-A")
        tag_b = described_class.compute_hmac_tag(payload, 42, 5, cluster_id: "cluster-B")
        expect(tag_a).not_to eq(tag_b)
      end

      it "raises ArgumentError on empty bytecode" do
        expect {
          described_class.compute_hmac_tag("", 42, 5, cluster_id: cluster_id)
        }.to raise_error(ArgumentError, /bytecode/)
      end

      it "raises ArgumentError on zero total_chunks" do
        expect {
          described_class.compute_hmac_tag(payload, 42, 0, cluster_id: cluster_id)
        }.to raise_error(ArgumentError, /lora_total_chunks/)
      end

      it "raises ArgumentError on nil version_id" do
        expect {
          described_class.compute_hmac_tag(payload, nil, 5, cluster_id: cluster_id)
        }.to raise_error(ArgumentError, /version_id/)
      end
    end

    describe ".build_hmac_trailer_chunks" do
      let(:hmac_tag) { ("\xAA" * 32).b }

      it "returns exactly 3 chunks" do
        chunks = described_class.build_hmac_trailer_chunks(hmac_tag, 5)
        expect(chunks.size).to eq(3)
      end

      it "each chunk is exactly 16 bytes (LoRa AES block)" do
        chunks = described_class.build_hmac_trailer_chunks(hmac_tag, 5)
        chunks.each { |c| expect(c.bytesize).to eq(16) }
      end

      it "first byte of each chunk is HMAC marker 0x9B" do
        chunks = described_class.build_hmac_trailer_chunks(hmac_tag, 5)
        chunks.each { |c| expect(c.unpack1("C")).to eq(0x9B) }
      end

      it "encodes seg_idx 1, 2, 3 in big-endian (bytes 1..2)" do
        chunks = described_class.build_hmac_trailer_chunks(hmac_tag, 5)
        seg_indices = chunks.map { |c| c[1..2].unpack1("n") }
        expect(seg_indices).to eq([ 1, 2, 3 ])
      end

      it "encodes lora_total_chunks consistently in bytes 3..4 (BE)" do
        chunks = described_class.build_hmac_trailer_chunks(hmac_tag, 5)
        totals = chunks.map { |c| c[3..4].unpack1("n") }
        expect(totals).to all(eq(5))
      end

      it "concatenated payloads (bytes 5..) reconstruct the original 32-byte tag" do
        chunks = described_class.build_hmac_trailer_chunks(hmac_tag, 5)
        # seg=1: bytes 0..10, seg=2: bytes 11..21, seg=3: bytes 22..31 + 1 PAD
        reconstructed = chunks[0][5..15] + chunks[1][5..15] + chunks[2][5..14]
        expect(reconstructed.b).to eq(hmac_tag)
      end

      it "raises ArgumentError on wrong tag length" do
        expect {
          described_class.build_hmac_trailer_chunks("\xAA" * 16, 5)
        }.to raise_error(ArgumentError, /32 bytes/)
      end
    end

    describe ".prepare with cluster_id (HMAC enabled)" do
      let(:payload) { ("R" * 60).b }  # 60 bytes → ~6 LoRa chunks

      it "appends 3 trailer packages after bytecode chunks" do
        bytecode_only = described_class.prepare(hmac_firmware, chunk_size: 512).fetch(:packages).to_a.size
        with_hmac     = described_class.prepare(hmac_firmware, chunk_size: 512, cluster_id: cluster_id).fetch(:packages).to_a.size

        expect(with_hmac).to eq(bytecode_only + 3)
      end

      it "exposes hmac_signed metadata in manifest" do
        manifest = described_class.prepare(hmac_firmware, chunk_size: 512, cluster_id: cluster_id).fetch(:manifest)
        expect(manifest[:hmac_signed]).to be true
        expect(manifest[:hmac_cluster_id]).to eq(cluster_id)
        expect(manifest[:total_packages]).to eq(manifest[:total_chunks] + 3)
      end

      it "exposes lora_total_chunks for cross-check with bytecode 0x99 header" do
        manifest = described_class.prepare(hmac_firmware, chunk_size: 512, cluster_id: cluster_id).fetch(:manifest)
        expected_lora_total = (60 + 2 + 4) / 11  # wire = 60 + pad(2) + CRC32(4) = 66 → 6
        expect(manifest[:lora_total_chunks]).to eq(expected_lora_total)
      end

      it "trailer chunks all have 0x9B marker" do
        packages = described_class.prepare(hmac_firmware, chunk_size: 512, cluster_id: cluster_id).fetch(:packages).to_a
        trailer = packages.last(3)
        trailer.each { |t| expect(t.unpack1("C")).to eq(0x9B) }
      end

      it "bytecode chunks come BEFORE trailer chunks (order matters for Soldier window)" do
        packages = described_class.prepare(hmac_firmware, chunk_size: 512, cluster_id: cluster_id).fetch(:packages).to_a
        last_bytecode_idx = packages.size - 4
        expect(packages[last_bytecode_idx].unpack1("C")).to eq(0x99)
        expect(packages[last_bytecode_idx + 1].unpack1("C")).to eq(0x9B)
      end
    end

    describe ".prepare without cluster_id (legacy / un-signed)" do
      let(:payload) { ("R" * 60).b }

      it "does NOT include trailer chunks (backward compat)" do
        packages = described_class.prepare(hmac_firmware, chunk_size: 512).fetch(:packages).to_a
        markers = packages.map { |p| p.unpack1("C") }
        expect(markers).to all(eq(0x99))
      end

      it "manifest does not include hmac metadata" do
        manifest = described_class.prepare(hmac_firmware, chunk_size: 512).fetch(:manifest)
        expect(manifest).not_to have_key(:hmac_signed)
        expect(manifest).not_to have_key(:total_packages)
      end
    end
  end
end
