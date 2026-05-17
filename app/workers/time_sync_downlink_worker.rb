# frozen_string_literal: true

require "timeout"

# [FW.20 / ARCH.41] Sends a time-sync-only CoAP downlink to the cluster's
# best-available gateway. The payload is empty — CoapEncryption prepends the
# CMD_TIME_SYNC envelope ([0x9C][ts_be:4]) automatically. Queen firmware
# (firmware/queen/main.c:1203-1204) detects inner_aligned == 0 and returns
# after updating its RTC, then broadcasts a time beacon to Soldiers via LoRa.
#
# Enqueued by TelemetryUnpackerService#check_z_divergence! whenever a warm
# Lorenz mismatch is recovered via the ARCH.41 epoch_day fallback, signalling
# that the sending Soldier likely has a stale RTC (VBAT-loss cold-start).
class TimeSyncDownlinkWorker
  include Sidekiq::Job
  include CoapEncryption

  sidekiq_options queue: "downlink", retry: 2

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
