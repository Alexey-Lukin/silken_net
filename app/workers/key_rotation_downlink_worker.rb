# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "timeout"

# [FW.17] Доставка `CMD_ROTATE_KEY 0x9E [target_version:u16le]+crc16` до
# Soldier'а через найкращу Queen його кластера. Сам ключ НІКОЛИ не летить
# ефіром — Soldier деривує K_{v+1} ратчетом (firmware/common/key_ratchet.h).
# Queen-реле: кадр їде CoAP'ом (AES-256-CBC + 0x9C time-sync envelope від
# CoapEncryption), Королева маршрутизує за маркером 0x9E у soldier_cmd_queue
# (FW.20-Q2) і проповідує Солдату LoRa-broadcast'ом.
#
# Enqueue — ЛИШЕ зсередини HardwareKeyService#rotate_tree_via_ratchet!, і
# ПІСЛЯ коміту БД-ротації [ARCH.59]. Гейт продубльовано тут
# defense-in-depth'ом: випадковий ручний enqueue у ECB-флот не повинен
# дійти до ефіру.
class KeyRotationDownlinkWorker
  include Sidekiq::Job
  include CoapEncryption

  sidekiq_options queue: "downlink", retry: 2

  # [FW.60] Вичерпані ретраї падали в DeadSet БЕЗ сліду в БД — а тут наслідок
  # важчий за time-sync: key_version уже закомічений ДО enqueue
  # (HardwareKeyService#rotate_tree_via_ratchet!), тож смерть job'а = ключ
  # ротований у БД, кадр 0x9E не доставлений. Recovery існує derivation'ом:
  # Dual-Key Grace (previous_aes_key_hex ≠ NULL) робить незавершену ротацію
  # видимою Downlink::PendingQueueService — Королева добере 0x9E наступним
  # poll'ом. Слід тут = гучність для оператора.
  sidekiq_retries_exhausted do |msg, _ex|
    device_uid, target_version = msg["args"]
    Rails.logger.error "🛑 [KeyRotationDownlink] Job для #{device_uid} (v#{target_version}) помер " \
                       "(#{msg['error_message'].to_s.truncate(120)}) — 0x9E добере poll-derivation (Grace-вікно)"
  end

  def perform(device_uid, target_version)
    unless HardwareKeyService.ratchet_dispatch_enabled?
      Rails.logger.warn("[KeyRotationDownlink] #{device_uid}: dispatch відхилено — " \
                        "#{HardwareKeyService::FW17_GATE_ENV} вимкнено (03_05 §3.8)")
      return
    end

    tree = Tree.find_by(did: device_uid)
    unless tree&.cluster_id
      Rails.logger.warn("[KeyRotationDownlink] #{device_uid}: дерево не знайдено або без кластера")
      return
    end

    gateway = best_gateway_for(tree.cluster_id)
    unless gateway
      Rails.logger.warn("[KeyRotationDownlink] #{device_uid}: кластер #{tree.cluster_id} без живої Queen — retry")
      raise "No eligible gateway for cluster #{tree.cluster_id}"
    end

    key_record = HardwareKey.find_by(device_uid: gateway.uid)
    return unless key_record&.binary_key.present?

    block = OtaPackagerService.build_rotate_key_block(target_version)
    encrypted = coap_encrypt(block, key_record.binary_key)

    begin
      Timeout.timeout(10) do
        CoapClient.put("coap://#{gateway.ip_address}/cmd/rotate_key", encrypted)
      end
      Rails.logger.info("[KeyRotationDownlink] #{device_uid}: 0x9E v#{target_version} queued via #{gateway.uid}")
    rescue Timeout::Error
      Rails.logger.warn("[KeyRotationDownlink] #{device_uid}: #{gateway.uid} timeout — retry")
      raise
    end
  end

  private

  # Та сама евристика, що TimeSyncDownlinkWorker: найсвіжіша жива Queen кластера.
  def best_gateway_for(cluster_id)
    Gateway.where(cluster_id: cluster_id)
           .where.not(ip_address: [ nil, "" ])
           .where.not(state: %w[maintenance faulty])
           .order(last_seen_at: :desc)
           .first
  end
end
