# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "openssl"
require "ed25519"

# [FW.23, ⚖️ founder 2026-10-05/06] Ключ печатки OTA-контракту — Ed25519 кластера.
#
# Бекенд підписує тіло контракту приватним ключем кластера, а Солдат тримає лише
# ПУБЛІЧНИЙ (Protected Flash 0x0803E800, magic "KPUB") і перевіряє печатку
# Monocypher'ом (`firmware/common/ota_seal.h`). Доти печаткою був HMAC-SHA256 під
# кластерним K_ota, що лежав на КОЖНОМУ вузлі кластера: один витягнутий вузол
# підписував контракт для всіх.
#
# Чому Ed25519, а не ECDSA-P256 (поправка примітиву, ратифікована 2026-10-06):
# печатка мусить бути ДЕТЕРМІНОВАНОЮ — пакет кампанії переготовлюють (`Ota::PackageStore`
# пакує при dispatch'і й знову, коли `GatewayStalenessSweepWorker` перегріває кеш), і випадковий nonce ECDSA
# зшив би трейлер із сегментів двох різних підписів; 32-байтний ключ лягає в той
# самий слот, де жив K_ota.
#
# Формула (той самий salt-домен кластера, що K_ota і KEYB; info — власний):
#   seed = HKDF-SHA256(ikm: PROVISIONING_MASTER_KEY, salt: "cluster:<id>",
#                      info: "silken-ota-ed25519-v1", length: 32)
#   (sk, pk) = Ed25519(seed)
#
# Master key — явний `master_key:` (фабрична Session, SEC.3 DI) або ENV-fallback для
# runtime-пакувальників; `SecurityError` без жодного (SEC.11 hard cutover).
# Протокол — docs/03_06 §4.
class OtaSealKeyService
  SEED_SIZE_BYTES = 32
  HKDF_INFO       = "silken-ota-ed25519-v1"

  # Приватний ключ кластера (`Ed25519::SigningKey`) — лише для підпису в процесі.
  def self.signing_key_for(cluster_id, master_key: nil)
    raise ArgumentError, "cluster_id is required" if cluster_id.blank?

    master_key ||= ENV["PROVISIONING_MASTER_KEY"]
    if master_key.blank?
      raise SecurityError,
            "PROVISIONING_MASTER_KEY ENV is required. Backend cannot derive the OTA seal " \
            "key without it (FW.23). See SEC.11 in docs/00_07_Action_Plan_Tracker.md."
    end

    seed = OpenSSL::KDF.hkdf(master_key, salt: "cluster:#{cluster_id}", info: HKDF_INFO,
                                         length: SEED_SIZE_BYTES, hash: "SHA256")
    Ed25519::SigningKey.new(seed)
  end

  # Публічний ключ кластера — 64 HEX (32 байти, верхній регістр): його пише фабрика
  # у слот "KPUB" і ним Солдат перевіряє печатку. Секретом не є.
  def self.public_key_hex_for(cluster_id, master_key: nil)
    signing_key_for(cluster_id, master_key: master_key).verify_key.to_bytes.unpack1("H*").upcase
  end
end
