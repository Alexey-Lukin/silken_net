# frozen_string_literal: true

require "net/http"
require "json"

module Filecoin
  # =========================================================================
  # 📦 FILECOIN ARCHIVE SERVICE (Вічна Пам'ять Планети)
  # =========================================================================
  # Архівує AuditLog записи до децентралізованого сховища IPFS/Filecoin
  # через API-шлюз (Web3.storage / Pinata). Кожен заархівований запис
  # отримує унікальний CID (Content Identifier), який неможливо підробити.
  #
  # Навіть якщо сервери зникнуть, будь-який дослідник зможе завантажити
  # криптографічно підтверджений звіт через Filecoin Explorer.
  # =========================================================================
  class ArchiveService
    # Pinata IPFS pinning endpoint (сумісний з Web3.storage та іншими шлюзами)
    PINATA_API_URL = "https://api.pinata.cloud/pinning/pinJSONToIPFS"

    # Таймаути для децентралізованого сховища (uploads бувають повільними)
    OPEN_TIMEOUT  = 15  # секунд на встановлення з'єднання
    READ_TIMEOUT  = 30  # секунд на очікування відповіді

    def initialize(audit_log)
      @audit_log = audit_log
    end

    # Головний метод — серіалізує AuditLog і завантажує на IPFS/Filecoin
    def archive!
      return if @audit_log.ipfs_cid.present?

      payload = build_payload
      response = upload_to_ipfs(payload)
      cid = extract_cid(response)

      @audit_log.update!(ipfs_cid: cid)

      Rails.logger.info "📦 [Filecoin] Archived AuditLog ##{@audit_log.id} → CID: #{cid}"

      cid
    end

    private

    # Формує JSON payload з даними аудит-логу для архівування
    def build_payload
      {
        pinataContent: {
          audit_log_id: @audit_log.id,
          organization_id: @audit_log.organization_id,
          action: @audit_log.action,
          chain_hash: @audit_log.chain_hash,
          metadata: @audit_log.metadata,
          auditable_type: @audit_log.auditable_type,
          auditable_id: @audit_log.auditable_id,
          created_at: @audit_log.created_at&.iso8601,
          archived_at: Time.current.iso8601
        },
        pinataMetadata: {
          name: "silkennet-audit-#{@audit_log.id}",
          keyvalues: {
            organization_id: @audit_log.organization_id.to_s,
            chain_hash: @audit_log.chain_hash.to_s,
            source: "silken_net"
          }
        }
      }
    end

    # Виконує HTTP POST до IPFS pinning API
    def upload_to_ipfs(payload)
      api_key = Rails.application.credentials.filecoin_api_key
      raise "🛑 [Filecoin] Missing filecoin_api_key in credentials" if api_key.blank?

      uri = URI.parse(PINATA_API_URL)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{api_key}"
      request.body = JSON.generate(payload)

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise "🛑 [Filecoin] IPFS upload failed (HTTP #{response.code}): #{response.body}"
      end

      JSON.parse(response.body)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.error "🛑 [Filecoin] IPFS Timeout: #{e.message}"
      raise "Filecoin IPFS Timeout: #{e.message}"
    rescue JSON::ParserError => e
      Rails.logger.error "🛑 [Filecoin] Invalid IPFS response: #{e.message}"
      raise "Filecoin IPFS Parse Error: #{e.message}"
    end

    # Витягує CID з відповіді Pinata API
    def extract_cid(response)
      cid = response["IpfsHash"]
      raise "🛑 [Filecoin] No CID returned from IPFS pinning service" if cid.blank?

      cid
    end
  end
end
