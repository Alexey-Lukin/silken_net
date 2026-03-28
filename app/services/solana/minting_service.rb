# frozen_string_literal: true

require "bigdecimal"

module Solana
  # =========================================================================
  # 🌊 SOLANA MINTING SERVICE (Паралельний мікро-платіжний модуль)
  # =========================================================================
  # Відповідає за миттєві мікро-винагороди на Solana Devnet/Mainnet.
  # Працює ПАРАЛЕЛЬНО з EVM (Polygon) — Solana для швидких мікро-платежів,
  # Polygon для великих RWA сертифікатів (SCC/SFC).
  #
  # Використовує Solana JSON RPC API напряму через Web3::HttpClient,
  # оскільки офіційного Ruby SDK для Solana не існує.
  #
  # Транзакція формується у бінарному форматі Solana:
  #   1. getLatestBlockhash → свіжий blockhash
  #   2. Серіалізація Message (header + account keys + blockhash + instructions)
  #   3. Ed25519 підпис через Ed25519Crypto::SigningService
  #   4. sendTransaction (base64) → реальний tx_signature
  # =========================================================================
  class MintingService
    # Solana Devnet RPC endpoint (перемикається на Mainnet через ENV)
    DEVNET_RPC_URL = "https://api.devnet.solana.com"

    # Мікро-винагорода за одиницю зростання біомаси (в USDC lamports, 1 USDC = 1_000_000 lamports)
    # 0.01 USDC = 10_000 lamports
    DEFAULT_MICRO_REWARD_LAMPORTS = 10_000

    # SPL Token Program ID (стандартний для всіх SPL токенів)
    SPL_TOKEN_PROGRAM_ID = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"

    # SPL Token Transfer instruction index (byte 3 = Transfer)
    SPL_TRANSFER_INSTRUCTION_INDEX = 3

    # Base58 alphabet (Bitcoin variant, used by Solana)
    BASE58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

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

      # Формуємо, підписуємо та відправляємо реальну Solana-транзакцію
      tx_signature = send_transfer_request(recipient_address, reward_lamports)

      # Створюємо запис у blockchain_transactions для аудиту (статус :sent — очікує підтвердження)
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

    # =========================================================================
    # PRODUCTION TRANSACTION FLOW (getLatestBlockhash → build → sign → send)
    # =========================================================================
    # Формує бінарну Solana-транзакцію, підписує Ed25519 і відправляє через sendTransaction.
    def send_transfer_request(recipient, amount_lamports)
      rpc_url = ENV.fetch("SOLANA_RPC_URL", DEVNET_RPC_URL)

      # [SECURITY]: SOLANA_WALLET_KEYPAIR обов'язковий для підпису транзакцій.
      # Hex-encoded 32-byte seed (приватний ключ Ed25519).
      keypair_hex = ENV["SOLANA_WALLET_KEYPAIR"]
      raise "🛑 [Solana] SOLANA_WALLET_KEYPAIR is required for transaction signing" if keypair_hex.blank?

      fee_payer = ENV.fetch("SOLANA_FEE_PAYER_PUBKEY") { raise "🛑 [Solana] SOLANA_FEE_PAYER_PUBKEY is required" }
      source_token_account = ENV.fetch("SOLANA_FEE_PAYER_TOKEN_ACCOUNT") { raise "🛑 [Solana] SOLANA_FEE_PAYER_TOKEN_ACCOUNT is required" }
      dest_token_account = ENV.fetch("SOLANA_DEST_TOKEN_ACCOUNT", nil)
      usdc_mint = ENV.fetch("SOLANA_USDC_MINT_ADDRESS") { raise "🛑 [Solana] SOLANA_USDC_MINT_ADDRESS is required" }

      # Для динамічних отримувачів — деривація ATA через RPC lookup
      dest_token_account = resolve_dest_token_account(rpc_url, recipient, usdc_mint) if dest_token_account.blank?

      # Крок 1: Отримання свіжого blockhash (необхідний для валідності транзакції)
      recent_blockhash = fetch_latest_blockhash(rpc_url)

      # Крок 2: Побудова бінарного повідомлення транзакції (Solana Message Format)
      message_bytes = build_spl_transfer_message(
        fee_payer:, source_token_account:, dest_token_account:,
        recent_blockhash:, amount_lamports:
      )

      # Крок 3: [MAINNET READY: Ed25519 SIGNED]
      # Підпис Message bytes приватним ключем Treasury-гаманця DAO.
      signature_bytes = sign_transaction_message(keypair_hex, message_bytes)

      # Крок 4: Формування повної транзакції (signatures + message) та broadcast
      broadcast_signed_transaction(rpc_url, signature_bytes, message_bytes)
    end

    # =========================================================================
    # RPC: getLatestBlockhash
    # =========================================================================
    def fetch_latest_blockhash(rpc_url)
      payload = {
        jsonrpc: "2.0",
        id: SecureRandom.uuid,
        method: "getLatestBlockhash",
        params: [ { commitment: "confirmed" } ]
      }

      response = execute_rpc_call(rpc_url, payload)

      blockhash = response&.dig("result", "value", "blockhash")
      raise "Solana RPC Error: Failed to fetch blockhash" if blockhash.blank?

      blockhash
    end

    # =========================================================================
    # RPC: getTokenAccountsByOwner (резолюція ATA для отримувача)
    # =========================================================================
    def resolve_dest_token_account(rpc_url, owner_address, mint_address)
      payload = {
        jsonrpc: "2.0",
        id: SecureRandom.uuid,
        method: "getTokenAccountsByOwner",
        params: [
          owner_address,
          { mint: mint_address },
          { encoding: "jsonParsed" }
        ]
      }

      response = execute_rpc_call(rpc_url, payload)

      accounts = response&.dig("result", "value")
      if accounts.is_a?(Array) && accounts.any?
        accounts.first["pubkey"]
      else
        raise "🛑 [Solana] No USDC token account found for recipient #{owner_address}. " \
              "Recipient must have an Associated Token Account for the USDC mint."
      end
    end

    # =========================================================================
    # BINARY SERIALIZATION: Solana Transaction Message
    # =========================================================================
    # Формат Solana Message (v0 legacy):
    #   [header: 3 bytes] [account_keys: N×32 bytes] [recent_blockhash: 32 bytes]
    #   [instructions: compact array]
    #
    # Header: [num_required_signatures, num_readonly_signed, num_readonly_unsigned]
    #
    # Для SPL Token Transfer:
    #   Account keys (ordered): fee_payer(signer,writable), source_ata(writable),
    #                           dest_ata(writable), spl_token_program(readonly)
    #   Instruction: program_id_index=3, accounts=[1,2,0], data=[3, amount_u64_le]
    def build_spl_transfer_message(fee_payer:, source_token_account:, dest_token_account:,
                                   recent_blockhash:, amount_lamports:)
      # Декодування Base58 адрес у 32-байтні публічні ключі
      fee_payer_bytes = decode_base58(fee_payer)
      source_ata_bytes = decode_base58(source_token_account)
      dest_ata_bytes = decode_base58(dest_token_account)
      token_program_bytes = decode_base58(SPL_TOKEN_PROGRAM_ID)
      blockhash_bytes = decode_base58(recent_blockhash)

      # Message Header: 1 signer (fee_payer), 0 readonly signed, 1 readonly unsigned (token program)
      header = [ 1, 0, 1 ].pack("C3")

      # Account keys (порядок: signer+writable → writable → readonly)
      account_keys = [
        fee_payer_bytes,        # index 0: signer, writable (fee payer + authority)
        source_ata_bytes,       # index 1: writable (source token account)
        dest_ata_bytes,         # index 2: writable (destination token account)
        token_program_bytes     # index 3: readonly (SPL Token Program)
      ]
      num_accounts = encode_compact_u16(account_keys.length)

      # SPL Token Transfer instruction data: [instruction_index(u8), amount(u64 LE)]
      instruction_data = [ SPL_TRANSFER_INSTRUCTION_INDEX ].pack("C") +
                          [ amount_lamports ].pack("Q<")

      # Instruction: program_id_index=3, account_indices=[1,2,0], data=instruction_data
      instruction = [
        3,                            # program_id_index (SPL Token Program)
        encode_compact_u16(3),        # num accounts
        [ 1, 2, 0 ].pack("C3"),      # account indices: source, dest, authority
        encode_compact_u16(instruction_data.bytesize),
        instruction_data
      ].map { |part| part.is_a?(String) ? part : part.to_s }.join

      # Збираємо повідомлення
      message = String.new(encoding: Encoding::BINARY)
      message << header
      message << num_accounts
      account_keys.each { |key| message << key }
      message << blockhash_bytes
      message << encode_compact_u16(1)  # num_instructions = 1
      message << instruction

      message
    end

    # =========================================================================
    # [MAINNET READY: Ed25519 SIGNED]
    # =========================================================================
    # Підпис бінарного повідомлення транзакції через Ed25519Crypto::SigningService.
    # keypair_hex — hex-encoded 32-byte seed (приватний ключ).
    # Повертає 64-байтний підпис у бінарному форматі.
    def sign_transaction_message(keypair_hex, message_bytes)
      signature_hex = Ed25519Crypto::SigningService.sign(keypair_hex, message_bytes)
      [ signature_hex ].pack("H*")
    rescue Ed25519Crypto::SigningService::SigningError => e
      raise "🛑 [Solana] Invalid SOLANA_WALLET_KEYPAIR: #{e.message}"
    end

    # =========================================================================
    # RPC: sendTransaction (broadcast signed transaction)
    # =========================================================================
    # Формує повну транзакцію (signature + message), кодує в Base64 і відправляє.
    # skipPreflight: false — Solana перевірить транзакцію перед включенням в блок.
    def broadcast_signed_transaction(rpc_url, signature_bytes, message_bytes)
      # Solana Transaction Format: [num_signatures (compact-u16)] [signatures] [message]
      transaction = String.new(encoding: Encoding::BINARY)
      transaction << encode_compact_u16(1)   # 1 signature
      transaction << signature_bytes          # 64-byte Ed25519 signature
      transaction << message_bytes            # serialized message

      encoded_tx = Base64.strict_encode64(transaction)

      payload = {
        jsonrpc: "2.0",
        id: SecureRandom.uuid,
        method: "sendTransaction",
        params: [
          encoded_tx,
          { encoding: "base64", skipPreflight: false, preflightCommitment: "confirmed" }
        ]
      }

      response = execute_rpc_call(rpc_url, payload)

      # sendTransaction повертає tx_signature у полі "result"
      tx_signature = response&.dig("result")
      if tx_signature.is_a?(String) && tx_signature.present?
        tx_signature
      else
        error_msg = response&.dig("error", "message") || "Unknown Solana RPC error"
        Rails.logger.error "🛑 [Solana RPC] #{error_msg}"
        raise "Solana RPC Error: #{error_msg}"
      end
    end

    # =========================================================================
    # HTTP TRANSPORT
    # =========================================================================
    def execute_rpc_call(rpc_url, payload)
      response = Web3::HttpClient.post(rpc_url,
        body: payload,
        open_timeout: 10,
        read_timeout: 15,
        service_name: "Solana"
      )

      response.parsed_body
    end

    # =========================================================================
    # AUDIT RECORD
    # =========================================================================
    # Зберігаємо Solana-транзакцію в blockchain_transactions для єдиного аудиту.
    # Статус :sent — транзакцію відправлено в мережу, очікує підтвердження блоку.
    # BlockchainConfirmationWorker підтвердить/відхилить пізніше.
    def record_transaction!(recipient, amount_lamports, tx_signature)
      wallet = @tree.wallet
      return unless wallet

      wallet.blockchain_transactions.create!(
        amount: format_usdc(amount_lamports).to_f,
        token_type: :carbon_coin,
        status: :sent,
        to_address: recipient,
        tx_hash: tx_signature,
        blockchain_network: "solana",
        chainlink_request_id: @telemetry_log.chainlink_request_id,
        zk_proof_ref: @telemetry_log.zk_proof_ref,
        notes: "Solana micro-reward: #{format_usdc(amount_lamports)} USDC (growth_points: #{@telemetry_log.growth_points})"
      )
    end

    # =========================================================================
    # UTILITY METHODS
    # =========================================================================

    # Конвертація lamports → USDC (6 decimals)
    def format_usdc(lamports)
      (BigDecimal(lamports.to_s) / 1_000_000).to_s("F")
    end

    # Base58 decode (Bitcoin/Solana alphabet) → 32-byte binary
    def decode_base58(address)
      num = 0
      address.each_char do |c|
        digit = BASE58_ALPHABET.index(c)
        raise "🛑 [Solana] Invalid Base58 character '#{c}' in address" if digit.nil?

        num = num * 58 + digit
      end

      # Convert to bytes (big-endian, pad to 32 bytes)
      bytes = []
      while num > 0
        bytes.unshift(num & 0xFF)
        num >>= 8
      end

      # Preserve leading zeros (Base58 leading '1's → 0x00 bytes)
      leading_ones = address.length - address.lstrip("1").length
      ([ 0 ] * leading_ones + bytes).pack("C*").rjust(32, "\x00")
    end

    # Solana compact-u16 encoding (variable-length unsigned integer)
    def encode_compact_u16(value)
      raise ArgumentError, "compact-u16 value out of range: #{value}" if value > 0xFFFF || value.negative?

      if value < 0x80
        [ value ].pack("C")
      elsif value < 0x4000
        [ (value & 0x7F) | 0x80, value >> 7 ].pack("CC")
      else
        [ (value & 0x7F) | 0x80, ((value >> 7) & 0x7F) | 0x80, value >> 14 ].pack("CCC")
      end
    end
  end
end
