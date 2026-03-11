# frozen_string_literal: true

require "eth"
require "digest"

module Ethereum
  # =========================================================================
  # ⚓ STATE ROOT ANCHORING SERVICE (L1 Ethereum Mainnet)
  # =========================================================================
  # Реалізує архітектуру "State Root Anchoring" (Rollup-стиль):
  # один раз на тиждень криптографічний хеш усього стану SilkenNet
  # записується у смарт-контракт на Ethereum Mainnet (32 байти).
  #
  # Це фінальна печатка, яка доводить усьому світу:
  # "Те, що сталося в SilkenNet до цього моменту, є істиною,
  #  і її більше ніколи не можна змінити."
  #
  # Gas-ефективність: тільки 1 запис (bytes32) на тиждень.
  # =========================================================================
  class StateAnchorService
    # ABI для контракту StateRootAnchor на Ethereum Mainnet
    ANCHOR_ABI = [
      {
        "inputs" => [
          { "internalType" => "bytes32", "name" => "root", "type" => "bytes32" }
        ],
        "name" => "storeStateRoot",
        "outputs" => [],
        "stateMutability" => "nonpayable",
        "type" => "function"
      }
    ].to_json

    # Генерує State Root — SHA256 дайджест, що об'єднує:
    # 1. Сумарний scc_balance усіх гаманців
    # 2. chain_hash останнього AuditLog
    # 3. Поточний timestamp (UTC)
    def generate_state_root
      total_scc = Wallet.sum(:scc_balance)
      latest_chain_hash = AuditLog.order(created_at: :desc, id: :desc).pick(:chain_hash) || "GENESIS"
      timestamp = Time.current.utc.iso8601

      payload = "#{total_scc}|#{latest_chain_hash}|#{timestamp}"
      Digest::SHA256.hexdigest(payload)
    end

    # Записує State Root у смарт-контракт на Ethereum Mainnet (L1).
    # Повертає хеш L1 транзакції.
    def anchor_to_l1!
      state_root = generate_state_root

      client = Eth::Client.create(ENV.fetch("ALCHEMY_ETHEREUM_RPC_URL"))
      anchor_key = Eth::Key.new(priv: ENV.fetch("ETHEREUM_ANCHOR_PRIVATE_KEY"))

      contract_address = ENV.fetch("ETHEREUM_ANCHOR_CONTRACT")
      contract = Eth::Contract.from_abi(
        name: "StateRootAnchor",
        address: contract_address,
        abi: ANCHOR_ABI
      )

      # Конвертуємо SHA256 hex string → bytes32 для EVM
      root_bytes = "0x#{state_root}"

      tx_hash = client.transact(
        contract, "storeStateRoot", root_bytes,
        sender_key: anchor_key, legacy: false
      )

      Rails.logger.info "⚓ [Ethereum L1] State Root anchored: #{state_root} → TX: #{tx_hash}"

      tx_hash
    rescue Net::OpenTimeout, Net::ReadTimeout, IOError => e
      Rails.logger.error "🛑 [Ethereum L1] Timeout: #{e.message}"
      raise "Ethereum L1 Timeout: #{e.message}"
    end
  end
end
