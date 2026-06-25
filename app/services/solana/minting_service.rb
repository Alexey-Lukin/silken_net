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

    # Мінімальний баланс оракула (SOL) для оплати газу транзакцій.
    # Аналог перевірки MATIC у BlockchainMintingService.
    # [E.51] Default value — fallback if SystemParameter not seeded yet.
    DEFAULT_MIN_ORACLE_BALANCE_SOL = 0.05

    # [E.61] TransferChecked валідує mint+decimals on-chain (захист від
    # wrong-mint/wrong-decimals), на відміну від «сліпого» Transfer.
    USDC_DECIMALS = 6
    SPL_TRANSFER_CHECKED_INSTRUCTION_INDEX = 12

    # [E.61] Kredis-дім акумульованих batch-виплат (Gas Optimizer).
    # Множина гаманців з ненульовим залишком — cron обходить лише її.
    PENDING_PAYOUT_WALLETS_KEY = "solana_pending_payout_wallets"

    # [E.61] Сервіс працює у двох режимах:
    #   • per-event  — initialize(telemetry_log): миттєва мікро-винагорода;
    #   • batch      — initialize(nil, wallet:): cron-виплата акумульованої суми.
    def initialize(telemetry_log = nil, wallet: nil)
      @telemetry_log = telemetry_log
      @tree = telemetry_log&.tree
      @wallet = wallet || @tree&.wallet
    end

    # Головний метод — виконує мікро-виплату на гаманець власника дерева
    def mint_micro_reward!
      validate_trustless_requirements!

      reward_lamports = calculate_reward
      return if reward_lamports.zero?

      recipient_address = resolve_recipient_address
      raise "🛑 [Solana] Missing Solana address for micro-payment (Tree or Organization)" if recipient_address.blank?

      # [E.61] Batch-режим: при ненульовому порозі акумулюємо винагороду в Kredis
      # замість окремої tx — per-event газ зрівнюється з винагородою при низьких
      # growth_points. SolanaBatchPayoutWorker виплатить суму, коли вона перетне
      # поріг. Backward-compat: поріг 0 → миттєва виплата (як було).
      return accumulate_pending_payout!(reward_lamports) if batch_threshold_lamports.positive?

      # Формуємо, підписуємо та відправляємо реальну Solana-транзакцію
      tx_signature = send_transfer_request(recipient_address, reward_lamports)

      # Створюємо запис у blockchain_transactions для аудиту (статус :sent — очікує підтвердження)
      record_transaction!(recipient_address, reward_lamports, tx_signature)

      Rails.logger.info "🌊 [Solana] Мікро-винагорода #{format_usdc(reward_lamports)} USDC → #{recipient_address} (TelemetryLog ##{@telemetry_log.id_value})"

      tx_signature
    end

    # [E.61] Виплата акумульованої суми одним TransferChecked (cron-driven).
    # Викликається з Solana::BatchPayoutService під per-wallet Kredis-локом.
    # [ARCH.45] Idempotent crash-window guard: durable intent-marker BlockchainTransaction
    # :pending з детермінованим signature створюється ДО broadcast. На краху між мережею і
    # DB BatchPayoutService бачить in-flight запис і звіряє on-chain (#signature_status),
    # замість сліпо платити вдруге. Повертає створений BlockchainTransaction (:sent).
    def batch_payout!(amount_lamports, event_count)
      raise "🛑 [Solana] batch_payout! потребує wallet" if @wallet.nil?
      return if amount_lamports.to_i.zero?

      recipient_address = resolve_recipient_address
      raise "🛑 [Solana] Missing Solana address for batch payout (Wallet ##{@wallet.id})" if recipient_address.blank?

      # sign-first: signature відомий до мережі → пишемо intent ДО broadcast.
      prepared = prepare_transfer(recipient_address, amount_lamports, checked: true)
      tx = record_batch_intent!(recipient_address, amount_lamports, event_count, prepared[:signature])

      broadcast_prepared(prepared)
      tx.mark_as_sent!(prepared[:signature])

      Rails.logger.info "🌊 [Solana] Batch-виплата #{format_usdc(amount_lamports)} USDC → #{recipient_address} (#{event_count} подій, Wallet ##{@wallet.id})"

      tx
    end

    # [ARCH.45] On-chain статус Solana-підпису через getSignatureStatuses.
    # → :confirmed (виконано) · :processing (ще в мережі) · :not_found (не дійшло/помилка — безпечно re-pay).
    def signature_status(tx_signature)
      rpc_url = ENV.fetch("SOLANA_RPC_URL", DEVNET_RPC_URL)
      payload = {
        jsonrpc: "2.0", id: SecureRandom.uuid, method: "getSignatureStatuses",
        params: [ [ tx_signature ], { searchTransactionHistory: true } ]
      }
      info = execute_rpc_call(rpc_url, payload)&.dig("result", "value")&.first
      return :not_found if info.nil?            # підпис не знайдено → не дійшло
      return :not_found if info["err"].present? # виконано з помилкою → кошти не пішли, безпечно re-pay

      %w[confirmed finalized].include?(info["confirmationStatus"]) ? :confirmed : :processing
    end

    private

    # [TRUSTLESS]: Ідентичні Guard Clauses з BlockchainMintingService.
    # Жодна транзакція не проходить без децентралізованої верифікації.
    def validate_trustless_requirements!
      unless @telemetry_log.verified_by_iotex?
        raise "Security Breach: Data not verified by IoTeX"
      end

      unless @telemetry_log.oracle_status_fulfilled?
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
      wallet = @wallet
      return nil unless wallet

      wallet.solana_public_address.presence ||
        wallet.organization&.solana_public_address.presence
    end

    # Per-event шлях — «сліпий» SPL Transfer (idx 3). Backward-compat.
    def send_transfer_request(recipient, amount_lamports)
      dispatch_transfer(recipient, amount_lamports, checked: false)
    end

    # [E.61] Batch шлях — SPL TransferChecked (idx 12): валідує mint+decimals on-chain.
    def send_transfer_checked_request(recipient, amount_lamports)
      dispatch_transfer(recipient, amount_lamports, checked: true)
    end

    # =========================================================================
    # PRODUCTION TRANSACTION FLOW (getLatestBlockhash → build → sign → send)
    # =========================================================================
    # Формує бінарну Solana-транзакцію, підписує Ed25519 і відправляє через sendTransaction.
    # `checked:` обирає інструкцію — спільний транспорт, різниться лише серіалізація (Крок 2).
    def dispatch_transfer(recipient, amount_lamports, checked:)
      broadcast_prepared(prepare_transfer(recipient, amount_lamports, checked: checked))
    end

    # [ARCH.45] Будує+підписує транзакцію БЕЗ broadcast. Solana tx_signature детермінований
    # після підпису (= base58 першого підпису), тож batch-виплата може записати durable
    # intent-marker з ним ДО мережі — на retry бачимо намір і не платимо наосліп (crash-window
    # double-pay). Solana дедуплікує повторний broadcast того ж підписаного tx у вікні blockhash.
    def prepare_transfer(recipient, amount_lamports, checked:)
      if ENV["SOLANA_RPC_URL"].blank? && Rails.env.production?
        raise "🛑 [Solana] SOLANA_RPC_URL is required in production — refusing Devnet fallback"
      end
      rpc_url = ENV.fetch("SOLANA_RPC_URL", DEVNET_RPC_URL)

      # [SECURITY]: SOLANA_WALLET_KEYPAIR обов'язковий для підпису транзакцій.
      # Hex-encoded 32-byte seed (приватний ключ Ed25519).
      keypair_hex = ENV["SOLANA_WALLET_KEYPAIR"]
      raise "🛑 [Solana] SOLANA_WALLET_KEYPAIR is required for transaction signing" if keypair_hex.blank?

      fee_payer = ENV.fetch("SOLANA_FEE_PAYER_PUBKEY") { raise "🛑 [Solana] SOLANA_FEE_PAYER_PUBKEY is required" }

      # [BLOCKER-1 FIX]: Guard clause — перевірка балансу оракула перед відправкою транзакції.
      # Аналог BlockchainMintingService.
      verify_oracle_balance!(rpc_url, fee_payer)

      source_token_account = ENV.fetch("SOLANA_FEE_PAYER_TOKEN_ACCOUNT") { raise "🛑 [Solana] SOLANA_FEE_PAYER_TOKEN_ACCOUNT is required" }
      dest_token_account = ENV.fetch("SOLANA_DEST_TOKEN_ACCOUNT", nil)
      usdc_mint = ENV.fetch("SOLANA_USDC_MINT_ADDRESS") { raise "🛑 [Solana] SOLANA_USDC_MINT_ADDRESS is required" }

      # Для динамічних отримувачів — деривація ATA через RPC lookup
      dest_token_account = resolve_dest_token_account(rpc_url, recipient, usdc_mint) if dest_token_account.blank?

      # Крок 1: Отримання свіжого blockhash (необхідний для валідності транзакції)
      recent_blockhash = fetch_latest_blockhash(rpc_url)

      # Крок 2: Побудова бінарного повідомлення транзакції (Solana Message Format)
      message_bytes =
        if checked
          build_spl_transfer_checked_message(
            fee_payer:, source_token_account:, dest_token_account:,
            usdc_mint:, recent_blockhash:, amount_lamports:
          )
        else
          build_spl_transfer_message(
            fee_payer:, source_token_account:, dest_token_account:,
            recent_blockhash:, amount_lamports:
          )
        end

      # Крок 3: [MAINNET READY: Ed25519 SIGNED]
      # Підпис Message bytes приватним ключем Treasury-гаманця DAO.
      signature_bytes = sign_transaction_message(keypair_hex, message_bytes)

      # [ARCH.45] tx_signature (base58 першого підпису) відомий ТУТ, до broadcast —
      # повертаємо все потрібне, broadcast виконує broadcast_prepared окремо.
      { rpc_url:, signature_bytes:, message_bytes:, signature: encode_base58(signature_bytes) }
    end

    # [ARCH.45] Broadcast попередньо підготованої (підписаної) транзакції — спільний хвіст
    # для per-event (dispatch_transfer) і batch (batch_payout!) шляхів.
    def broadcast_prepared(prepared)
      broadcast_signed_transaction(prepared[:rpc_url], prepared[:signature_bytes], prepared[:message_bytes])
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
      instruction = String.new(encoding: Encoding::BINARY)
      instruction << [ 3 ].pack("C")                              # program_id_index (SPL Token Program)
      instruction << encode_compact_u16(3)                         # num accounts
      instruction << [ 1, 2, 0 ].pack("C3")                       # account indices: source, dest, authority
      instruction << encode_compact_u16(instruction_data.bytesize) # data length
      instruction << instruction_data                              # instruction data

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
    # [E.61] BINARY SERIALIZATION: SPL TransferChecked
    # =========================================================================
    # На відміну від Transfer, TransferChecked несе mint-акаунт і decimals, тож
    # SPL-рантайм валідує їх on-chain (захист від wrong-mint/wrong-decimals).
    # Розкладка акаунтів/інструкції — нижче у коді.
    def build_spl_transfer_checked_message(fee_payer:, source_token_account:, dest_token_account:,
                                           usdc_mint:, recent_blockhash:, amount_lamports:)
      fee_payer_bytes = decode_base58(fee_payer)
      source_ata_bytes = decode_base58(source_token_account)
      dest_ata_bytes = decode_base58(dest_token_account)
      mint_bytes = decode_base58(usdc_mint)
      token_program_bytes = decode_base58(SPL_TOKEN_PROGRAM_ID)
      blockhash_bytes = decode_base58(recent_blockhash)

      # Header: 1 signer (fee_payer=authority), 0 readonly-signed, 2 readonly-unsigned (mint + token program)
      header = [ 1, 0, 2 ].pack("C3")

      account_keys = [
        fee_payer_bytes,        # index 0: signer, writable (fee payer + authority)
        source_ata_bytes,       # index 1: writable (source token account)
        dest_ata_bytes,         # index 2: writable (destination token account)
        mint_bytes,             # index 3: readonly (mint — валідується on-chain)
        token_program_bytes     # index 4: readonly (SPL Token Program)
      ]
      num_accounts = encode_compact_u16(account_keys.length)

      # TransferChecked instruction data: [instruction_index(u8), amount(u64 LE), decimals(u8)]
      instruction_data = [ SPL_TRANSFER_CHECKED_INSTRUCTION_INDEX ].pack("C") +
                          [ amount_lamports ].pack("Q<") +
                          [ USDC_DECIMALS ].pack("C")

      # Instruction: program_id_index=4, account_indices=[1,3,2,0], data=instruction_data
      instruction = String.new(encoding: Encoding::BINARY)
      instruction << [ 4 ].pack("C")                              # program_id_index (SPL Token Program)
      instruction << encode_compact_u16(4)                         # num accounts
      instruction << [ 1, 3, 2, 0 ].pack("C4")                    # account indices: source, mint, dest, authority
      instruction << encode_compact_u16(instruction_data.bytesize) # data length
      instruction << instruction_data                              # instruction data

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
      wallet = @wallet
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
    # [BLOCKER-1 FIX]: Oracle Balance Guard
    # =========================================================================
    # Перевіряє баланс SOL на гаманці оракула перед відправкою транзакції.
    # [E.51] Threshold configurable через SystemParameter (governance-aware, 24h cache).
    def verify_oracle_balance!(rpc_url, fee_payer_pubkey)
      min_balance_sol = (SystemParameter.current(:oracle_min_balance_sol, default: DEFAULT_MIN_ORACLE_BALANCE_SOL) || DEFAULT_MIN_ORACLE_BALANCE_SOL).to_f
      min_balance_lamports = (min_balance_sol * 1_000_000_000).to_i

      payload = {
        jsonrpc: "2.0",
        id: SecureRandom.uuid,
        method: "getBalance",
        params: [ fee_payer_pubkey, { commitment: "confirmed" } ]
      }

      response = execute_rpc_call(rpc_url, payload)
      balance = response&.dig("result", "value").to_i

      if balance < min_balance_lamports
        raise "🚨 [Solana] Критично низький баланс Оракула: #{balance} lamports " \
              "(мінімум: #{min_balance_lamports} lamports / #{min_balance_sol} SOL)"
      end
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
      raw = ([ 0 ] * leading_ones + bytes).pack("C*")

      # Solana public keys are exactly 32 bytes; pad short values, reject oversized ones
      if raw.bytesize > 32
        raise "🛑 [Solana] Invalid address: decoded #{raw.bytesize} bytes, expected ≤ 32"
      end

      raw.rjust(32, "\x00")
    end

    # [ARCH.45] Base58 encode (Solana/Bitcoin alphabet) — зворотний до decode_base58.
    # 64-байтний Ed25519 підпис → base58 tx_signature (те саме, що повертає sendTransaction),
    # обчислене локально ДО broadcast для durable intent-marker.
    def encode_base58(bytes)
      num = bytes.bytes.inject(0) { |acc, b| (acc * 256) + b }
      enc = +""
      while num.positive?
        num, rem = num.divmod(58)
        enc.prepend(BASE58_ALPHABET[rem])
      end
      # Провідні нульові байти → провідні '1' (інваріант Base58).
      leading_zeros = bytes.bytes.take_while(&:zero?).length
      ("1" * leading_zeros) + enc
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

    # =========================================================================
    # [E.61] BATCH ACCUMULATION (Gas Optimizer)
    # =========================================================================
    # Поріг батчингу у lamports; governance-aware через SystemParameter.
    # 0 → batch вимкнено (per-event). Значення/обґрунтування — канон 05_01 §8.
    def batch_threshold_lamports
      usdc = SystemParameter.current(:solana_batch_threshold_usdc, default: 0).to_f
      (usdc * 1_000_000).to_i
    end

    # Акумулює винагороду per-wallet у Kredis; виплату зробить SolanaBatchPayoutWorker,
    # коли сума перетне поріг. Лічильник подій — для аудит-нотатки агрегованої tx.
    def accumulate_pending_payout!(reward_lamports)
      wallet_id = @wallet.id
      Kredis.counter("solana_pending_payouts:#{wallet_id}").increment(by: reward_lamports)
      Kredis.counter("solana_pending_payout_count:#{wallet_id}").increment
      Kredis.set(PENDING_PAYOUT_WALLETS_KEY).add(wallet_id.to_s)

      Rails.logger.info "🌊 [Solana] Акумульовано #{format_usdc(reward_lamports)} USDC для Wallet ##{wallet_id} (batch-режим)"
      nil
    end

    # [ARCH.45] Intent-marker: :pending запис із детермінованим signature ДО broadcast.
    # batch_payout! переведе :pending→:sent через mark_as_sent! після успішної мережі.
    # `events:N` у notes — для детермінованого Kredis-settle на reconcile (BatchPayoutService),
    # щоб concurrent надбавки між виплатою й підтвердженням не загубились.
    def record_batch_intent!(recipient, amount_lamports, event_count, signature)
      @wallet.blockchain_transactions.create!(
        amount: format_usdc(amount_lamports).to_f,
        token_type: :carbon_coin,
        status: :pending,
        to_address: recipient,
        tx_hash: signature,
        blockchain_network: "solana",
        notes: "Solana batch micro-reward: #{format_usdc(amount_lamports)} USDC (#{event_count} подій акумульовано) [E.61] events:#{event_count}"
      )
    end
  end
end
