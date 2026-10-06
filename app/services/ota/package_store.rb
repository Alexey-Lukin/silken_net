# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [FW.60 · SEC.22] Пакунки OTA-кампанії (bytecode-чанки + трейлер Ed25519-печатки
# кластера, FW.23) — один дім ключа кешу між ПИСАЧАМИ й ЧИТАЧЕМ.
#
# Пакують лише процеси, що мають PROVISIONING_MASTER_KEY (прод-boot-гард не пускає
# без нього жоден, крім coap): диспетчер кампанії (web) — до спалення hiwater, і
# OTA-сторож (`GatewayStalenessSweepWorker`, job) — прогрів на промаху, щоб витіснення
# Solid Cache не поховало кампанію, яку та сама версія вже не перезапустить
# (hiwater → «rollback»). Читає coap-процес poll-тракту, якому ключа не дано за
# SEC.22, і сам ⛔ НЕ пакує ніколи: доти пакував він, тож на anchor-coap кожна
# кампанія була темною за побудовою, а fail-closed це ховав (⚖️ делеговано
# 2026-09-27 — присуд у картці `Ota::PackageStore`, 04_02).
#
# Байти тут не секретні: bytecode відкритий, печатка — підпис, що й так летить ефіром.
# ⚠️ Спільність тримають Solid Cache (БД `<POSTGRES_DATABASE>_cache`) і простір імен
# `DEPLOYMENT_SLOT` — coap.env задає обидва тими самими значеннями, що web/job
# (пін `spec/deploy/anchor_coap_env_spec.rb`). Розійдуться — кожне читання
# промахнеться, і кампанію впіймає лише 24-годинний OTA-сторож.
module Ota
  module PackageStore
    module_function

    # Страховка від застарілого тегу (ротація master-key), не межа кампанії:
    # живу кампанію сторож перепрогріває на першому ж промаху.
    TTL = 1.day

    def read(firmware_id, cluster_id)
      Rails.cache.read(key(firmware_id, cluster_id))
    end

    # Без master-key кидає SecurityError — гучно, у писача, до будь-якого стану.
    def warm!(firmware, cluster_id)
      packages = OtaPackagerService.prepare(
        firmware, chunk_size: OtaChunkable::CHUNK_SIZE, cluster_id: cluster_id
      )[:packages].to_a
      Rails.cache.write(key(firmware.id, cluster_id), packages, expires_in: TTL)
      packages
    end

    def key(firmware_id, cluster_id) = "fw60/ota_packages/#{firmware_id}/#{cluster_id}"
  end
end
