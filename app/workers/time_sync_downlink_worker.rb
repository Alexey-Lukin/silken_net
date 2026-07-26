# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "timeout"

# [FW.20 / ARCH.41] Sends a time-sync-only CoAP downlink to the cluster's
# best-available gateway. The payload is empty — CoapEncryption prepends the
# CMD_TIME_SYNC envelope ([0x9C][ts_be:4]) automatically. Queen firmware
# (firmware/queen/main.c, the `inner_aligned == 0` branch — cited by symbol, not by
# line: the previous line-number citation had already drifted onto an unrelated
# HAL_Delay) detects the empty inner payload and returns
# after updating its RTC, then broadcasts a time beacon to Soldiers via LoRa.
#
# Enqueued by TelemetryUnpackerService#check_z_divergence! whenever a warm
# Lorenz mismatch is recovered via the ARCH.41 epoch_day fallback, signalling
# that the sending Soldier likely has a stale RTC (VBAT-loss cold-start).
class TimeSyncDownlinkWorker
  include Sidekiq::Job
  include CoapEncryption

  sidekiq_options queue: "downlink", retry: 2

  # [FW.60] Вичерпані ретраї падали в DeadSet БЕЗ сліду. Наслідок м'який —
  # стану в БД нема, а Королева однаково отримує свіжий [0x9C][ts:4] у КОЖНІЙ
  # poll-відповіді (CoapEncryption) — тож слід тут = видимість, не recovery.
  sidekiq_retries_exhausted do |msg, _ex|
    cluster_id = msg["args"]&.first
    Rails.logger.error "🛑 [TimeSyncDownlink] Job для кластера #{cluster_id} помер " \
                       "(#{msg['error_message'].to_s.truncate(120)}) — Королева синкнеться наступним poll'ом"
  end

  def perform(cluster_id)
    gateway = best_gateway_for(cluster_id)
    return unless gateway

    key_record = HardwareKey.find_by(device_uid: gateway.uid)
    return unless key_record&.binary_key.present?

    encrypted = coap_encrypt("".b, key_record.binary_key)

    begin
      Timeout.timeout(10) do
        CoapClient.put("coap://#{gateway.ip_address}/cmd/time_sync", encrypted)
      end
      Rails.logger.info("[TimeSyncDownlink] Cluster #{cluster_id}: time beacon queued via #{gateway.uid}")
    rescue Timeout::Error
      Rails.logger.warn("[TimeSyncDownlink] Cluster #{cluster_id}: #{gateway.uid} timeout — will retry")
      raise
    end
  end

  private

  def best_gateway_for(cluster_id)
    Gateway.where(cluster_id: cluster_id)
           .where.not(ip_address: [ nil, "" ])
           .where.not(state: %w[maintenance faulty])
           .order(last_seen_at: :desc)
           .first
  end
end
