# SPDX-License-Identifier: AGPL-3.0-or-later
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
        # [FW.53] len-поле додано: Queen більше не вгадує довжину
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
        # [FW.53] Регресія старого бага: повний чанк мусить
        # нести рівно 512 байт і чесний len — Queen раніше обрізала його до 500.
        package = described_class.prepare(firmware, chunk_size: 512)[:packages].first
        len = package[5..6].unpack1("n")
        expect(len).to eq(512)
        # 7 header + 512 data + 2 CRC = 521
        expect(package.bytesize).to eq(521)
      end
    end

    # [FW.53] Wire-потік LoRa-шару: Soldier рахує отримане як
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
  # ⚖️ [FW.23, founder 2026-10-05/06] OTA seal — Ed25519 of the cluster key
  # =========================================================================
  describe "seal trailer (FW.23)" do
    let(:seal_firmware) do
      instance_double(BioContractFirmware, id: 42, version: "1.0.0", binary_payload: payload, binary_sha256: "abc123")
    end
    let(:cluster_id) { "cluster-test-1" }
    let(:payload) { "RITE\x03\x00\x00\x00\xAA\xBB\xCC".b }

    def verify_key(cluster) = Ed25519::VerifyKey.new([ OtaSealKeyService.public_key_hex_for(cluster) ].pack("H*"))

    describe ".compute_seal" do
      it "returns a 64-byte Ed25519 signature that verifies under the cluster public key" do
        seal = described_class.compute_seal(payload, 42, 5, cluster_id: cluster_id)

        expect(seal.bytesize).to eq(64)
        expect(verify_key(cluster_id).verify(seal, described_class.seal_message(payload, 42, 5))).to be(true)
      end

      # Несуче: пакет кампанії переготовлюють (`Ota::PackageStore` — при dispatch'і й знову,
      # коли `GatewayStalenessSweepWorker` перегріває кеш), а Королева ретранслює ті сегменти, що дотягнула —
      # випадковий підпис зшив би трейлер із двох печаток.
      it "is deterministic — re-packaging a campaign yields the same seal" do
        first = described_class.compute_seal(payload, 42, 5, cluster_id: cluster_id)

        expect(described_class.compute_seal(payload, 42, 5, cluster_id: cluster_id)).to eq(first)
      end

      # Золотий вектор: ті самі байти перевіряє прошивка (firmware/test/test_ota_seal.c) —
      # міняєш тут → перегенеруй там, і навпаки.
      it "matches the cross-language golden vector the firmware verifies" do
        stub_const("ENV", ENV.to_h.merge("PROVISIONING_MASTER_KEY" => "silken-fw23-golden-master-key"))
        body = "RITE\x03\x00\x00\x00".b + (0xA0..0xAD).map(&:chr).join.b

        expect(OtaSealKeyService.public_key_hex_for("cluster-golden-1"))
          .to eq("90B7DBB747630A9E2DDE9AE86C2B28B3F43421C553C6196AB5F61FD6732FC146")
        expect(described_class.compute_seal(body, 42, 3, cluster_id: "cluster-golden-1").unpack1("H*").upcase)
          .to eq("4D0C902D735A2A1145ED5BE8352C082649B284702DEF22310C55B53FDF055C7F" \
                 "F967B4E5DE87E1890630BD25A07C97CF4E0682E33F109AEAF4B54C96C150670A")
      end

      it "binds version and chunk count — a relabelled or truncated campaign does not verify" do
        seal = described_class.compute_seal(payload, 42, 5, cluster_id: cluster_id)
        key = verify_key(cluster_id)

        expect { key.verify(seal, described_class.seal_message(payload, 43, 5)) }.to raise_error(Ed25519::VerifyError)
        expect { key.verify(seal, described_class.seal_message(payload, 42, 4)) }.to raise_error(Ed25519::VerifyError)
      end

      it "isolates clusters — another cluster's public key rejects the seal" do
        seal = described_class.compute_seal(payload, 42, 5, cluster_id: "cluster-A")

        expect { verify_key("cluster-B").verify(seal, described_class.seal_message(payload, 42, 5)) }
          .to raise_error(Ed25519::VerifyError)
      end

      it "raises ArgumentError on empty bytecode, zero total_chunks and nil version_id" do
        expect { described_class.compute_seal("", 42, 5, cluster_id: cluster_id) }.to raise_error(ArgumentError, /bytecode/)
        expect { described_class.compute_seal(payload, 42, 0, cluster_id: cluster_id) }.to raise_error(ArgumentError, /lora_total_chunks/)
        expect { described_class.compute_seal(payload, nil, 5, cluster_id: cluster_id) }.to raise_error(ArgumentError, /version_id/)
      end
    end

    describe ".build_seal_trailer_chunks" do
      let(:seal) { (0...64).map { |i| (0x40 + i).chr }.join.b }
      let(:chunks) { described_class.build_seal_trailer_chunks(seal, 5, 42) }

      it "returns 7 sixteen-byte chunks marked 0x9B with seg_idx 1..7 and the total in bytes 3..4 (BE)" do
        expect(chunks.size).to eq(7)
        expect(chunks.map(&:bytesize)).to all(eq(16))
        expect(chunks.map { |c| c.getbyte(0) }).to all(eq(0x9B))
        expect(chunks.map { |c| c.byteslice(1, 2).unpack1("n") }).to eq((1..7).to_a)
        expect(chunks.map { |c| c.byteslice(3, 2).unpack1("n") }).to all(eq(5))
      end

      it "seg 1..6 reconstruct the 64-byte seal; seg 6 carries 9 bytes and 2 NUL PAD" do
        expect(chunks.first(6).map { |c| c.byteslice(5, 11) }.join.byteslice(0, 64)).to eq(seal)
        expect(chunks[5].byteslice(14, 2)).to eq("\x00\x00".b)
      end

      it "seg 7 carries version_id as 4-byte big-endian (part of the signed message)" do
        chunk = described_class.build_seal_trailer_chunks(seal, 5, 0x01020304).last

        expect(chunk.byteslice(5, 4).unpack1("N")).to eq(0x01020304)
      end

      it "raises ArgumentError on a wrong seal length or nil version_id" do
        expect { described_class.build_seal_trailer_chunks(("\xAA" * 32).b, 5, 42) }.to raise_error(ArgumentError, /seal must be 64/)
        expect { described_class.build_seal_trailer_chunks(seal, 5, nil) }.to raise_error(ArgumentError, /version_id/)
      end
    end

    describe ".prepare with cluster_id (sealed)" do
      let(:payload) { ("R" * 60).b }
      let(:prepared) { described_class.prepare(seal_firmware, chunk_size: 512, cluster_id: cluster_id) }

      it "appends 7 trailer packages (0x9B) after the bytecode chunks (0x99)" do
        bytecode_only = described_class.prepare(seal_firmware, chunk_size: 512).fetch(:packages).to_a.size
        packages = prepared.fetch(:packages).to_a

        expect(packages.size).to eq(bytecode_only + 7)
        expect(packages.first(bytecode_only).map { |p| p.getbyte(0) }).to all(eq(0x99))
        expect(packages.last(7).map { |p| p.getbyte(0) }).to all(eq(0x9B))
      end

      it "exposes the seal metadata and the wire package count in the manifest" do
        manifest = prepared.fetch(:manifest)

        expect(manifest).to include(sealed: true, seal_cluster_id: cluster_id)
        expect(manifest[:total_packages]).to eq(manifest[:total_chunks] + 7)
        expect(manifest[:lora_total_chunks]).to be_a(Integer)
      end

      # Солдат хешує padded bytecode БЕЗ CRC32-хвоста (`Ota_Seal_Try_Finalize`).
      it "the trailer verifies under the cluster public key over the padded bytecode the Soldier hashes" do
        trailer = prepared.fetch(:packages).to_a.last(7)
        seal = trailer.first(6).map { |c| c.byteslice(5, 11) }.join.byteslice(0, 64)
        pad_len = (described_class::LORA_MTU - ((payload.bytesize + described_class::LORA_CRC32_BYTES) % described_class::LORA_MTU)) %
                  described_class::LORA_MTU
        message = described_class.seal_message(payload + ("\x00" * pad_len), 42, prepared.dig(:manifest, :lora_total_chunks))

        expect(trailer.last.byteslice(5, 4).unpack1("N")).to eq(42)
        expect(verify_key(cluster_id).verify(seal, message)).to be(true)
      end

      it "prepares byte-identical packages twice — no stitched trailer for the Queen" do
        again = described_class.prepare(seal_firmware, chunk_size: 512, cluster_id: cluster_id)

        expect(again.fetch(:packages).to_a).to eq(prepared.fetch(:packages).to_a)
      end
    end

    describe ".prepare without cluster_id (legacy / unsealed)" do
      let(:payload) { ("R" * 60).b }

      it "includes no trailer and no seal metadata" do
        prepared = described_class.prepare(seal_firmware, chunk_size: 512)

        expect(prepared.fetch(:packages).to_a.map { |p| p.getbyte(0) }).to all(eq(0x99))
        expect(prepared.fetch(:manifest)).not_to have_key(:sealed)
        expect(prepared.fetch(:manifest)).not_to have_key(:total_packages)
      end
    end
  end
end
