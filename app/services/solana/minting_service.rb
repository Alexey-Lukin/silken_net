# frozen_string_literal: true

require "net/http"
require "json"
require "bigdecimal"

module Solana
  # =========================================================================
  # 🌊 SOLANA MINTING SERVICE (Паралельний мікро-платіжний модуль)
  # =========================================================================
  # Відповідає за миттєві мікро-винагороди на Solana Devnet/Mainnet.
  # Працює ПАРАЛЕЛЬНО з EVM (Polygon) — Solana для швидких мікро-платежів,
  # Polygon для великих RWA сертифікатів (SCC/SFC).
  #
  # Використовує Solana JSON RPC API напряму через Net::HTTP,
  # оскільки офіційного Ruby SDK для Solana не існує.
  # =========================================================================
  class MintingService
    # Solana Devnet RPC endpoint (перемикається на Mainnet через ENV)
    DEVNET_RPC_URL = "https://api.devnet.solana.com"

    # Мікро-винагорода за одиницю зростання біомаси (в USDC lamports, 1 USDC = 1_000_000 lamports)
    # 0.01 USDC = 10_000 lamports
    DEFAULT_MICRO_REWARD_LAMPORTS = 10_000

    # SPL Token Program ID (стандартний для всіх SPL токенів)
    SPL_TOKEN_PROGRAM_ID = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"

    def initialize(telemetry_log)
      @telemetry_log = telemetry_log
      @tree = telemetry_log.tree
    end

    # Головний метод — виконує мікро-виплату на гаманець власника дерева
    def mint_micro_reward!
      validate_trustless_requirements!

      reward_lamports = calculate_reward
      return if reward_lamports.zero?

      recipient_address = resolve_recipient_address
      raise "🛑 [Solana] Missing Solana address for micro-payment (Tree or Organization)" if recipient_address.blank?

      # Формуємо та відправляємо JSON RPC запит до Solana
      tx_signature = send_transfer_request(recipient_address, reward_lamports)

      # Створюємо запис у blockchain_transactions для аудиту
      record_transaction!(recipient_address, reward_lamports, tx_signature)

      Rails.logger.info "🌊 [Solana] Мікро-винагорода #{format_usdc(reward_lamports)} USDC → #{recipient_address} (TelemetryLog ##{@telemetry_log.id_value})"

      tx_signature
    end

    private

    # [TRUSTLESS]: Ідентичні Guard Clauses з BlockchainMintingService.
    # Жодна транзакція не проходить без децентралізованої верифікації.
    def validate_trustless_requirements!
      unless @telemetry_log.verified_by_iotex?
        raise "Security Breach: Data not verified by IoTeX"
      end

      unless @telemetry_log.oracle_status == "fulfilled"
        raise "Security Breach: Chainlink Oracle consensus not fulfilled"
      end
    end

    # Розрахунок мікро-винагороди на основі зростання біомаси дерева.
    # growth_points з телеметрії визначає розмір бонусу.
    def calculate_reward
      growth = @telemetry_log.growth_points.to_i
      return 0 if growth <= 0

      # Базова винагорода + бонус за кожну одиницю росту
      base = DEFAULT_MICRO_REWARD_LAMPORTS
      bonus = (growth * 100) # 100 lamports за кожен growth_point (0.0001 USDC)

      base + bonus
    end

    # Пріоритет адреси: Solana-адреса дерева → Організації
    # Solana-адреси зберігаються у полі solana_public_address (Base58, 32-44 символи)
    def resolve_recipient_address
      wallet = @tree.wallet
      return nil unless wallet

      wallet.solana_public_address.presence ||
        wallet.organization&.solana_public_address.presence
    end

    # Формує JSON RPC payload для Solana та відправляє через Net::HTTP.
    # В production це буде реальний SPL Token Transfer.
    # Поточна реалізація — симуляція для Devnet з логуванням payload.
    def send_transfer_request(recipient, amount_lamports)
      rpc_url = ENV.fetch("SOLANA_RPC_URL", DEVNET_RPC_URL)
      # [DEVNET]: Placeholder defaults for simulation mode. In production, these ENV vars
      # MUST be set to real Solana keypair addresses. The service currently uses
      # simulateTransaction, not sendTransaction — no real funds are at risk.
      fee_payer = ENV.fetch("SOLANA_FEE_PAYER_PUBKEY", "SiLkEnNeT1111111111111111111111111111111111")
      mint_authority = ENV.fetch("SOLANA_MINT_AUTHORITY_PUBKEY", fee_payer)
      usdc_mint = ENV.fetch("SOLANA_USDC_MINT_ADDRESS", "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU")

      # JSON RPC payload для simulateTransaction (Devnet safe)
      payload = {
        jsonrpc: "2.0",
        id: SecureRandom.uuid,
        method: "simulateTransaction",
        params: [
          build_transfer_instruction(fee_payer, mint_authority, recipient, usdc_mint, amount_lamports),
          { encoding: "base64", commitment: "confirmed" }
        ]
      }

      response = execute_rpc_call(rpc_url, payload)

      # Генеруємо детермінований хеш транзакції для аудиту
      # В production — це буде реальний tx_signature від sendTransaction
      if response && response["result"]
        "solana:sim:#{Digest::SHA256.hexdigest("#{recipient}:#{amount_lamports}:#{Time.current.to_i}")}"
      else
        error_msg = response&.dig("error", "message") || "Unknown Solana RPC error"
        Rails.logger.error "🛑 [Solana RPC] #{error_msg}"
        raise "Solana RPC Error: #{error_msg}"
      end
    end

    # Побудова інструкції SPL Token Transfer (Base64-encoded placeholder)
    def build_transfer_instruction(fee_payer, mint_authority, recipient, usdc_mint, amount)
      # В production тут буде реальна серіалізована Solana-транзакція
      # (Compact Array of Instructions → Base64). Наразі — placeholder для Devnet.
      Base64.strict_encode64(
        JSON.generate({
          type: "spl_token_transfer",
          fee_payer: fee_payer,
          mint_authority: mint_authority,
          recipient: recipient,
          mint: usdc_mint,
          amount: amount,
          program_id: SPL_TOKEN_PROGRAM_ID
        })
      )
    end

    # Виконує HTTP POST до Solana JSON RPC endpoint
    def execute_rpc_call(rpc_url, payload)
      uri = URI.parse(rpc_url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 10
      http.read_timeout = 15

      request = Net::HTTP::Post.new(uri.path.presence || "/")
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)

      response = http.request(request)
      JSON.parse(response.body)

    rescue Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.error "🛑 [Solana] RPC Timeout: #{e.message}"
      raise "Solana RPC Timeout: #{e.message}"
    rescue JSON::ParserError => e
      Rails.logger.error "🛑 [Solana] Invalid RPC response: #{e.message}"
      raise "Solana RPC Parse Error: #{e.message}"
    end

    # Зберігаємо Solana-транзакцію в blockchain_transactions для єдиного аудиту
    def record_transaction!(recipient, amount_lamports, tx_signature)
      wallet = @tree.wallet
      return unless wallet

      wallet.blockchain_transactions.create!(
        amount: format_usdc(amount_lamports).to_f,
        token_type: :carbon_coin,
        status: :confirmed,
        to_address: recipient,
        tx_hash: tx_signature,
        blockchain_network: "solana",
        chainlink_request_id: @telemetry_log.chainlink_request_id,
        zk_proof_ref: @telemetry_log.zk_proof_ref,
        notes: "Solana micro-reward: #{format_usdc(amount_lamports)} USDC (growth_points: #{@telemetry_log.growth_points})"
      )
    end

    # Конвертація lamports → USDC (6 decimals)
    def format_usdc(lamports)
      (BigDecimal(lamports.to_s) / 1_000_000).to_s("F")
    end
  end
end
