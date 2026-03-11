# frozen_string_literal: true

require "net/http"
require "json"

module Filecoin
  # =========================================================================
  # 🔍 FILECOIN VERIFICATION SERVICE (Верифікація Вічної Пам'яті)
  # =========================================================================
  # Перевіряє, що дані на IPFS відповідають локальному аудит-логу.
  # Дослідник може взяти CID з блокчейну та завантажити криптографічно
  # підтверджений звіт через IPFS Gateway.
  # =========================================================================
  class VerificationService
    # Публічний IPFS Gateway для читання (не потребує API ключа)
    # Може бути перевизначений через ENV для інших середовищ
    IPFS_GATEWAY_URL = ENV.fetch("FILECOIN_GATEWAY_URL", "https://gateway.pinata.cloud/ipfs")

    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 20

    def initialize(audit_log)
      @audit_log = audit_log
    end

    # Перевіряє, що CID існує і chain_hash на IPFS збігається з локальним
    def verify!
      cid = @audit_log.ipfs_cid
      raise "🛑 [Filecoin] AuditLog ##{@audit_log.id} has no IPFS CID" if cid.blank?

      remote_data = fetch_from_ipfs(cid)
      compare_chain_hash(remote_data)
    end

    private

    # Завантажує JSON-дані з IPFS Gateway за CID
    def fetch_from_ipfs(cid)
      uri = URI.parse("#{IPFS_GATEWAY_URL}/#{cid}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Get.new(uri.request_uri)
      request["Accept"] = "application/json"

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise "🛑 [Filecoin] IPFS fetch failed (HTTP #{response.code}): #{response.body}"
      end

      JSON.parse(response.body)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.error "🛑 [Filecoin] IPFS Gateway Timeout: #{e.message}"
      raise "Filecoin IPFS Gateway Timeout: #{e.message}"
    rescue JSON::ParserError => e
      Rails.logger.error "🛑 [Filecoin] Invalid IPFS data: #{e.message}"
      raise "Filecoin IPFS Parse Error: #{e.message}"
    end

    # Порівнює chain_hash з IPFS з локальним chain_hash
    def compare_chain_hash(remote_data)
      remote_hash = remote_data["chain_hash"]
      local_hash = @audit_log.chain_hash

      if remote_hash == local_hash
        Rails.logger.info "✅ [Filecoin] Verified AuditLog ##{@audit_log.id} — chain_hash matches"
        { verified: true, cid: @audit_log.ipfs_cid, chain_hash: local_hash }
      else
        Rails.logger.warn "⚠️ [Filecoin] MISMATCH for AuditLog ##{@audit_log.id}: local=#{local_hash}, remote=#{remote_hash}"
        { verified: false, cid: @audit_log.ipfs_cid, local_hash: local_hash, remote_hash: remote_hash }
      end
    end
  end
end
