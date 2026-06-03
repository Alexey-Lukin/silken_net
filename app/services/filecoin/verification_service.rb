# frozen_string_literal: true

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

    # Перевіряє цілісність архіву: (1) E.60 content-CID guard — детектує ex-post
    # підміну вмісту; (2) chain_hash збіг із локальним записом.
    def verify!
      cid = @audit_log.ipfs_cid
      raise "🛑 [Filecoin] AuditLog ##{@audit_log.id} has no IPFS CID" if cid.blank?

      remote_data = fetch_from_ipfs(cid)

      swap = detect_content_swap(remote_data)
      return swap if swap

      compare_chain_hash(remote_data)
    end

    private

    # E.60 CID-witness guard (`05_02 §E.60`): незалежно перераховуємо детермінований
    # content-CID із віддаленого вмісту та з локального запису. Будь-яка розбіжність
    # (підмінений вміст або підроблений вбудований CID) → fail-fast.
    # Legacy-архіви без вбудованого `content_cid` пропускаємо (лишається chain_hash).
    def detect_content_swap(remote_data)
      claimed = remote_data["content_cid"]
      return nil if claimed.blank?

      recomputed = Filecoin::ArchiveService.content_cid(remote_data)
      expected   = Filecoin::ArchiveService.content_cid(Filecoin::ArchiveService.content_attrs(@audit_log))
      return nil if claimed == recomputed && recomputed == expected

      Rails.logger.warn "🛑 [Filecoin] CID MISMATCH (ex-post swap?) AuditLog ##{@audit_log.id}: " \
                        "claimed=#{claimed}, recomputed=#{recomputed}, expected=#{expected}"
      { verified: false, reason: "cid_mismatch", cid: @audit_log.ipfs_cid,
        claimed_cid: claimed, recomputed_cid: recomputed, expected_cid: expected }
    end

    # Завантажує JSON-дані з IPFS Gateway за CID
    def fetch_from_ipfs(cid)
      response = Web3::HttpClient.get("#{IPFS_GATEWAY_URL}/#{cid}",
        headers: { "Accept" => "application/json" },
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT,
        service_name: "Filecoin"
      )

      response.parsed_body
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
