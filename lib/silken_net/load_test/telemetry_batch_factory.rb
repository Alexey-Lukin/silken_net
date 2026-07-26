# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "openssl"
require "securerandom"

module SilkenNet
  module LoadTest
    # = ===================================================================
    # 🏭 TelemetryBatchFactory — детермінований генератор вхідного
    #    навантаження пайплайну (INF.23 load-harness)
    # = ===================================================================
    #
    # Один дім для «що слати»: байт-валідні CoAP CON PUT
    # /telemetry/batch/<uid> та AES-256-CBC батчі, байт-ідентичні емісії
    # Королеви (дзеркало bin/forest_simulator §3-4 ↔ decrypt_aes воркера
    # ↔ TelemetryUnpackerService PAYLOAD_FORMAT). Seedable за конструкцією:
    # sensor-значення й DID-послідовність задає викликач, тож drain-прогін
    # відтворюваний (той самий Lorenz-вхід). Випадкові лише MID та IV —
    # семантику обробки вони не міняють.
    #
    # Два рівні навантаження:
    #   • coap_datagram   — чистий intake-контракт (демон parse-ить CoAP і
    #     enqueue-ить; payload НЕ декриптить — це робить воркер), тож для
    #     виміру стелі demon-parse байти payload неважливі.
    #   • encrypted_batch — валідний AES-256-CBC батч provisioned Королеви
    #     (повний drain-каскад: decrypt → Lorenz → DCI → commit → fanout).
    module TelemetryBatchFactory
      module_function

      AES_BLOCK = 16

      # Homeostasis wire-band (SilkenNet::Attractor::GP_HOMEO_MIN..MAX) —
      # synthetic сенсори лишаються emission-eligible, щоб drain проходив
      # УВЕСЬ money-каскад (wallet.credit!), а не відсікався як noise/anomaly.
      DEFAULT_GROWTH_POINTS = 18

      # 21-байт ECB chunk — дзеркало forest_simulator packing ↔
      # TelemetryUnpackerService::PAYLOAD_FORMAT ("N n c C n C C a4"):
      #   [DID:4 BE][RSSI:1] ‖ [DID:4][Vcap:2][Temp:1i][Acoustic:1][Metab:2]
      #   [Status:1][TTL:1][Pad:4] (Pad[0..1] = firmware_id BE).
      # Дефолти свідомо у Sanity Bounds (voltage 0..5000, temp -45..90) +
      # homeostasis, щоб пакет проходив valid_sensor_data? і повний каскад.
      def chunk(did_int:, firmware_id: 0, rssi: 60, voltage_mv: 4000,
                temperature_c: 20, acoustic: 3, metabolism_s: 30,
                growth_points: DEFAULT_GROWTH_POINTS, ttl: 3, bio_status: 0)
        status_byte  = ((bio_status & 0x03) << 5) | (growth_points & 0x1F)
        firmware_pad = [ firmware_id, 0 ].pack("n n")
        l2_header    = [ did_int, rssi ].pack("N C")
        # Pack-формат — SSOT-дзеркало, беремо з дому (drift-guard: змінюється ТАМ).
        l3_payload   = [ did_int, voltage_mv, temperature_c, acoustic,
                         metabolism_s, status_byte, ttl, firmware_pad ]
                       .pack(TelemetryUnpackerService::PAYLOAD_FORMAT)
        l2_header + l3_payload
      end

      # Плаский (нешифрований) батч із chunk'ів для послідовності DID.
      def plaintext_batch(dids, **chunk_opts)
        dids.map { |did_int| chunk(did_int: did_int, **chunk_opts) }.join
      end

      # AES-256-CBC: [IV:16][CT:N*16], zero-pad, padding=0 — байт-ідентично
      # Королеві (forest_simulator) й дзеркально decrypt_aes воркера.
      def encrypt(plaintext, key)
        cipher = OpenSSL::Cipher.new("aes-256-cbc")
        cipher.encrypt
        cipher.key     = key
        cipher.padding = 0
        iv  = cipher.random_iv
        pad = (AES_BLOCK - (plaintext.bytesize % AES_BLOCK)) % AES_BLOCK
        iv + cipher.update(plaintext + ("\x00".b * pad)) + cipher.final
      end

      # Готовий encrypted батч provisioned Королеви (key = binary_key 32B).
      def encrypted_batch(key:, dids:, **chunk_opts)
        encrypt(plaintext_batch(dids, **chunk_opts), key)
      end

      # CoAP CON PUT /telemetry/batch/<uid> — wire-дзеркало Королеви
      # (CoapClient.build_put). payload будь-який: демон його не декриптить.
      def coap_datagram(gateway_uid:, payload:)
        CoapClient.build_put(
          message_id: SecureRandom.random_number(0xFFFF) + 1,
          path: "/telemetry/batch/#{gateway_uid}",
          payload: payload
        )
      end

      # Синтетичний payload заданого розміру для structural intake-flood
      # (демон-parse не залежить від вмісту — лише від наявності/розміру).
      def random_payload(byte_size)
        SecureRandom.bytes(byte_size)
      end
    end
  end
end
