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
  # Відповідь несе власний тег (`seal_reply` нижче), прив'язаний до тегу запиту.
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

    # [FW.60 ⚖️ делеговано 2026-10-09] MAC над ВІДПОВІДДЮ — дзеркало `Pull_Mac_Reply_Tag`
    # (`firmware/queen/pull_mac.h`), golden-вектор спільний. Конверт [IV:16][AES-256-CBC KEYC]
    # ховав, ЩО каже Rails, але не доводив, що казав Rails: зміна IV переписує перший блок
    # відкритого тексту (час і OTA-hint), а стару відповідь можна повторити. Тег — 16 Б
    # хвостом, і він чинний лише для свого запиту:
    #   K_rmac = HMAC-SHA256(KEYC, REPLY_LABEL)
    #   tag    = HMAC-SHA256(K_rmac, REPLY_VERSION \n m_hex \n ‖ конверт)[0, 16]
    REPLY_LABEL = "silken-reply-mac-v1"
    REPLY_VERSION = "silken-reply-v1"
    REPLY_TAG_LEN = 16

    # Конверт + тег. Кличеться лише після `authentic?`, тож `m=` і KEYC тут уже є.
    def self.seal_reply(gateway:, result:, envelope:)
      m_hex = result.request.uri_query.find { _1.start_with?("m=") }.delete_prefix("m=").downcase
      envelope.b + reply_tag(keyc: gateway.hardware_key.coap_binary_key, m_hex: m_hex, envelope: envelope)
    end

    def self.reply_tag(keyc:, m_hex:, envelope:)
      k_rmac = OpenSSL::HMAC.digest("SHA256", keyc, REPLY_LABEL)
      OpenSSL::HMAC.digest("SHA256", k_rmac, "#{REPLY_VERSION}\n#{m_hex}\n".b + envelope.b).byteslice(0, REPLY_TAG_LEN)
    end

    def self.hex(keyc:, route:, uid:, mid:, raw_query:)
      k_mac = OpenSSL::HMAC.digest("SHA256", keyc, LABEL)
      canonical = [ VERSION, route, uid, mid.to_s, *raw_query.reject { _1.start_with?("m=") } ].join("\n")
      OpenSSL::HMAC.hexdigest("SHA256", k_mac, canonical)[0, HEX_LEN]
    end
  end
end
