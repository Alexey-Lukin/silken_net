# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Downlink
  # [SEC.38] MAC над Queen-pull запитом (`poll/<uid>`, `ota/<uid>`). ⚖️ founder 2026-09-27.
  #
  # Доти `CoapGate` шукав шлюз за uid з Uri-Path і вірив query будь-якого відправника:
  # підроблений `fw=` закривав OTA-кампанію шлюзу, що її не отримав, а сам poll рухав
  # стан наказів. Шифрований конверт ВІДПОВІДІ цього не лікував — він ховає, що каже
  # Rails, а не доводить, хто питає.
  #
  # Дзеркало — `firmware/queen/pull_mac.h`; спільний golden-вектор тримають
  # `firmware/test/test_pull_mac.c` і `spec/services/downlink/pull_mac_spec.rb`.
  #   K_mac     = HMAC-SHA256(KEYC, LABEL) — підключ, щоб AES-256 KEYC і HMAC не ділили ключ
  #   canonical = VERSION \n route \n uid \n mid ( \n q )* — q = Uri-Query у порядку
  #               надсилання, БЕЗ самої m=
  #   запит несе  m=<перші 16 байт HMAC-SHA256(K_mac, canonical) у hex>
  # ⚠️ Стеля: свіжості MAC не дає — перехоплений справжній запит можна повторити. Повтор
  # нічого не підробляє (fw= і cmd= справжні), лише перевидає голову черги.
  module PullMac
    LABEL = "silken-poll-mac-v1"
    VERSION = "silken-pull-v1"
    HEX_LEN = 32
    ROUTES = { downlink_poll: "poll", ota_chunk_fetch: "ota" }.freeze

    # KEYC — той, що Королева тримає ЗАРАЗ (`HardwareKey#coap_binary_key`): у Dual-Key
    # Grace це попередній ключ, бо новий доїжджає лише re-provision'ом.
    def self.authentic?(gateway:, result:)
      keyc = gateway.hardware_key&.coap_binary_key
      return false if keyc.nil?

      raw_query = result.request.uri_query
      given = raw_query.find { _1.start_with?("m=") }&.delete_prefix("m=")
      return false unless given&.match?(/\A\h{#{HEX_LEN}}\z/o)

      expected = hex(keyc: keyc, route: ROUTES.fetch(result.status), uid: result.gateway_uid,
                     mid: result.request.message_id, raw_query: raw_query)
      ActiveSupport::SecurityUtils.secure_compare(given.downcase, expected)
    end

    def self.hex(keyc:, route:, uid:, mid:, raw_query:)
      k_mac = OpenSSL::HMAC.digest("SHA256", keyc, LABEL)
      canonical = [ VERSION, route, uid, mid.to_s, *raw_query.reject { _1.start_with?("m=") } ].join("\n")
      OpenSSL::HMAC.hexdigest("SHA256", k_mac, canonical)[0, HEX_LEN]
    end
  end
end
