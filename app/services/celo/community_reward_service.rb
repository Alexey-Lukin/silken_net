# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "eth"

module Celo
  # = ===================================================================
  # 🌿 CELO COMMUNITY REWARD SERVICE (Позитивний зворотний зв'язок)
  # = ===================================================================
  # Якщо BurnCarbonTokensWorker — це "Батіг" (Slashing за смерть лісу),
  # то Celo — це "Пряник" (cUSD на смартфон лісника за ідеальне здоров'я лісу).
  #
  # Використовує стандартний ERC-20 інтерфейс для переказу cUSD (Celo Dollar)
  # з системного казначейства на гаманець організації.
  #
  # [ARCH.50] Money-path-hardened (4-й ARCH.45 сиблінг): durable `:pending` intent
  # ПЕРЕД broadcast + dedup на ЛОГІЧНИЙ `reward_date` (не `created_at`) ВСЕРЕДИНІ
  # lock + Celo-aware reconcile + deterministic-vs-transient error split. Дзеркало
  # Solana-BatchPayout (auto-heal), не slash (escalate-flood — зайве на reward-обсязі).
  # = ===================================================================
  class CommunityRewardService
    # Мінімальний ERC-20 ABI — лише transfer(address,uint256)
    ERC20_TRANSFER_ABI = [
      {
        "inputs" => [
          { "internalType" => "address", "name" => "to", "type" => "address" },
          { "internalType" => "uint256", "name" => "amount", "type" => "uint256" }
        ],
        "name" => "transfer",
        "outputs" => [
          { "internalType" => "bool", "name" => "", "type" => "bool" }
        ],
        "stateMutability" => "nonpayable",
        "type" => "function"
      }
    ].to_json

    # ⛔ ТУТ БУЛА `DEFAULT_RPC_URL` — hardcoded-фолбек на `alfajores-forno.celo-testnet.org`.
    # ⚖️ ЗНЯТО 2026-08-31 (founder), і зняття, а не перецілення, обрано з підставою:
    # фолбек існує рівно щоб пережити брак конфіга, а на ГРОШОВОМУ шляху це і є небезпека,
    # не зручність — тож правило E.49, збудоване цю небезпеку поліціювати, стає непотрібним,
    # а не переобґрунтованим. Хост при цьому був іще й МЕРТВИЙ (NXDOMAIN, виміряно 2026-08-30
    # з позитивним контролем `forno.celo.org` → `0xa4ec`), тобто «фолбек» вів у нікуди.
    # ⛔ НЕ ПОВЕРТАТИ в жодній формі — ані на `celo-sepolia`, ані на Alchemy: код-сайд-дефолт,
    # що тихо підставляє ІНШИЙ ЧЕЙН, обходить саме те питання, задля якого існує вісь
    # `WEB3_CHAIN_ENV` (слот на чужому ендпоінті мусить падати ГУЧНО). Конфігурований каскад
    # `RPC_FALLBACK_ENV_KEYS` нижче лишається — він перемикає ендпоінти В МЕЖАХ оголошеного
    # чейну, і це інший клас.
    # 🔑 Споживачів було ЧОТИРИ, і греп по хосту бачив лише два — решта брали константу
    # ІМЕНЕМ (`#award_reward!` · `CeloConfirmationWorker` · `MintingRollbackService` ·
    # `Treasury::MonitorService`). Урок переживає зняття: перелічуй ФОРМИ посилання, не
    # входження одного літерала. ⚠️ Четвертий споживач вимагав ІНШОГО ліку — він читальний,
    # і fail-loud там зламав би дормантний свіп; деталь у його власному місці.

    # [E.49] RPC FALLBACK CASCADE для Celo. Якщо `CELO_RPC_URL` недоступний
    # (Net::ReadTimeout / HTTP 429 / Errno::ECONNREFUSED), Web3::ResilientClient
    # автоматично переключиться на наступний URL з цього списку.
    RPC_FALLBACK_ENV_KEYS = %w[
      CELO_RPC_URL_FALLBACK_1
      CELO_RPC_URL_FALLBACK_2
    ].freeze

    # Фіксована винагорода за ідеальний стан кластера (5 cUSD)
    REWARD_AMOUNT = "5.0"

    # cUSD має 18 десяткових знаків (стандарт ERC-20)
    TOKEN_DECIMALS = 18

    # Максимальний stress_index для отримання винагороди
    MAX_STRESS_INDEX = 0.2

    # Мінімальний баланс оракула (CELO) для оплати газу транзакцій.
    MIN_ORACLE_BALANCE_WEI = 0.05 * (10**18)

    # [ARCH.50] eth-gem error messages that mean the node DEFINITELY rejected the tx —
    # it never entered the mempool → safe to fail the intent and re-pay next cycle.
    REJECTED_PATTERNS = /execution reverted|insufficient funds|intrinsic gas|gas required exceeds|invalid sender|out of gas/i

    # Messages that mean a tx with this nonce was ALREADY submitted (the prior attempt
    # MAY have broadcast) → AMBIGUOUS: do NOT re-pay, leave the intent for reconcile.
    AMBIGUOUS_PATTERNS = /nonce too low|already known|replacement transaction underpriced|already imported/i

    def initialize(cluster, target_date)
      @cluster = cluster
      @target_date = target_date
    end

    def reward_community!
      # Guard Clause 1: Перевірка здоров'я кластера через AiInsight
      insight = fetch_health_insight
      return unless eligible_for_reward?(insight)

      # Guard Clause 2: Перевірка наявності гаманця організації
      organization = @cluster.organization
      return unless organization&.crypto_public_address.present?

      # Підключення до Celo RPC — Thread-cached RPC client з fallback cascade [E.49]
      # ⚖️ Без `fallback:` — `client_for` робить `ENV.fetch`, тобто `KeyError` на незаданій
      # змінній. Це навмисно: fail-loud на money-шляху, та сама форма, що в `OracleSigner`.
      client = Web3::RpcConnectionPool.client_for(
        "CELO_RPC_URL",
        fallback_env_keys: RPC_FALLBACK_ENV_KEYS
      )
      # [ARCH.50] Виділений Celo-підписант — ізолює blast-radius від Polygon-флоту (ARCH.49).
      # Легасі-fallback на спільний base retired [INF.22]. Чейни мають незалежні
      # nonce-простори, тож ключ — лише security.
      # [SEC.17] Деривація — через seam `Web3::OracleSigner` (ENV-дефолт незмінний).
      signer = Web3::OracleSigner.for(:celo)

      # [BLOCKER-1 FIX]: Guard clause — перевірка балансу оракула перед відправкою.
      balance = client.get_balance(signer.address)
      # 🔴 [ВИМІРЯНО 2026-09-05] НУЛЬ ≠ ВИЧЕРПАННЯ, і формулювання це стверджувало.
      # Питання founder-а: «куди зʼїдаються кошти, якщо користувачів і дерев нема?»
      # Перевірено on-chain: `nonce = 0` — з адреси не пішло ЖОДНОЇ транзакції, тобто
      # нічого не витрачалось, гаманець просто НЕ ПОПОВНЮВАЛИ. Але текст казав
      # «критично НИЗЬКИЙ», тобто твердив ВИЧЕРПАННЯ й посилав шукати витік, якого нема.
      # ⛔ Клас — той самий, що нуль-ініціалізація gauge у Grafana-правилах (S2.4):
      # нуль-як-ПОЧАТОК нерозрізненний із нулем-як-НАСЛІДОК, і кожен алерт, писаний
      # через вичерпання, стверджує хибну половину. Дискримінатор дешевий і НЕ потребує
      # зайвого RPC: рівно нуль = стан НАЛАШТУВАННЯ, менше мінімуму = вичерпання.
      if balance.zero?
        raise "🚨 [Celo] Оракул НЕ ПРОВІЖИНЕНО: баланс рівно 0 — стан НАЛАШТУВАННЯ, не вичерпання. ⛔ Не шукати витік: звір `nonce`."
      elsif balance < MIN_ORACLE_BALANCE_WEI
        raise "🚨 [Celo] Баланс Оракула НИЖЧИЙ ЗА МІНІМУМ: #{balance} (поріг #{MIN_ORACLE_BALANCE_WEI}) — витрачено більше, ніж поповнено."
      end

      cusd_contract_address = ENV.fetch("CELO_CUSD_CONTRACT_ADDRESS")
      contract = Eth::Contract.from_abi(name: "CeloUSD", address: cusd_contract_address, abi: ERC20_TRANSFER_ABI)

      amount_in_wei = Web3::WeiConverter.to_wei(REWARD_AMOUNT, TOKEN_DECIMALS)
      recipient = organization.crypto_public_address
      # [ARCH.49/ARCH.50] Chain-prefixed lock key → Celo не контендить хибно з Polygon base-key.
      lock_key = "lock:web3:celo:oracle:#{signer.address}"

      intent = nil
      begin
        Kredis.lock(lock_key, expires_in: 30.seconds, after_timeout: :raise) do
          # [ARCH.50] dedup + intent + broadcast ВСЕ всередині lock (серіалізовано):
          #   - dedup на ЛОГІЧНИЙ reward_date закриває детермінований #0 (target_date≠created_at);
          #   - dedup всередині lock закриває pre-lock TOCTOU #2;
          #   - `:pending` intent ПЕРЕД transact закриває crash-window #1.
          return if reward_already_sent?

          intent = create_reward_intent!(recipient, insight: insight)
          tx_hash = signer.transact(
            client, contract, "transfer", recipient, amount_in_wei,
            legacy: false
          )
          intent.mark_as_sent!(tx_hash) if tx_hash.present?
        end

        # Пост-lock: блок завершився (не dedup-return, не виняток) → intent створено.
        if intent.status_sent?
          # [ARCH.50] Озброюємо Celo-aware reconcile (revert→re-payable; confirm→done).
          CeloConfirmationWorker.perform_in(30.seconds, intent.id, intent.created_at.iso8601)
          Rails.logger.info "🌿 [Celo ReFi] Винагорода #{REWARD_AMOUNT} cUSD → #{organization.name} (Кластер: #{@cluster.name}, Дата: #{@target_date})"
          intent.tx_hash
        else
          # transact повернув порожній hash БЕЗ винятку (malformed ack) → intent лишається
          # `:pending` (dedup блокує re-pay); стале :pending підбирає ARCH.64
          # CeloRewardReconcileWorker → :manual_review (людська звірка, не blind re-pay).
          Rails.logger.warn "⚠️ [Celo ReFi] Порожній tx_hash для кластера #{@cluster.name} — intent ##{intent.id} лишається :pending."
          nil
        end
      rescue Kredis::LockTimeout => e
        # [ARCH.50] Lock не взято → блок (dedup+intent+transact) НЕ виконувався → intent немає →
        # безпечно retry-ити. Не CIRCUIT_BREAKER_ERROR; re-raise для Sidekiq retry.
        raise e
      rescue StandardError => e
        handle_transact_failure(intent, e)
      end
    end

    private

    # 🔴 [SLASH-1] ПРАВИЛО КОНСЕНСУСУ — «найгірше джерело», а не «яке записалось першим».
    #
    # Unique-індекс `idx_ai_insights_unique_report` несе `model_source`, тож два
    # oracle-consensus рядки на кластер за добу легальні за дизайном. Доти тут стояв голий
    # `.first`, і дефект був ТИХИЙ, а не «плаваючий»: AR без явного порядку додає
    # `ORDER BY id ASC`, тобто гейт виплати систематично питав НАЙСТАРІШЕ джерело — при
    # розбіжності (одне бачить стрес, друге ні) 5 cUSD залежали від того, хто записався
    # раніше.
    #
    # ⚖️ Присуд тут виводиться з НЕЗВОРОТНОСТІ, а не зі смаку: виплата необоротна, тож
    # консервативний бік — «будь-яке джерело, що бачить стрес або фрод, тримає гроші».
    # Дзеркало щойно ратифікованого в INS.1: чужа непевність може ТРИМАТИ виплату, і лише
    # власний чистий доказ її рухає.
    #
    # Порядок несе обидві осі: спершу `fraud_detected` (true поперед false), потім
    # найбільший стрес. ⚠️ `NULL` у PG при `DESC` іде ПЕРШИМ — і це саме те, що треба:
    # рядок без виміру виграє сортування й натрапляє на `stress_index.nil?`-гард нижче,
    # тобто «не виміряно» теж тримає виплату.
    def fetch_health_insight
      @cluster.ai_insights
              .daily_health_summary
              .for_date(@target_date)
              .order(fraud_detected: :desc, stress_index: :desc)
              .first
    end

    # [SLASH-1, founder-ратифікація] День з vm_error-кадром (софт-збій прошивки)
    # СВІДОМО reward-eligible: stress_index за нього = 0.0 (vm_error ≠ біо-стрес),
    # сенсорна половина кадру жива (зламаний лише Лоренц-статус), а карати дерево
    # за НАШ баг — «не карати жертву». Емісія захищена окремо (vm_error → 0 GP
    # per-frame); маскування стресу через vm_error домінується фейк-homeostasis
    # (ловить DCI/attest, не цей гейт). Хронічний vm_error = ops-тріаж
    # (firmware_fault-алерт), не reward-стеля.
    def eligible_for_reward?(insight)
      return false if insight.nil?
      return false if insight.stress_index.nil?
      return false if insight.stress_index > MAX_STRESS_INDEX
      return false if insight.fraud_detected?

      true
    end

    # [ARCH.50] reward_date = логічний audit-день (Date), розв'язаний від `created_at`
    # (час запису). target_date може бути Time (адмінський виклик) → `.to_date`.
    def reward_date_value
      @target_date.to_date
    end

    # [ARCH.50] Dedup на ЛОГІЧНИЙ reward_date (коректність), created_at-вікно — ЛИШЕ
    # partition-pruning підказка (рядок пишеться ~reward_date+1день; same-day double-fire
    # обидва в [reward_date, reward_date+2д)). Статус-сет = усе, ОКРІМ :failed (failed →
    # re-payable). Вкл. :pending/:manual_review → можливо-landed спроба блокує re-pay.
    def reward_already_sent?
      rdate = reward_date_value

      # [ARCH.64#2] dedup-вікно [rdate, rdate+2д) прив'язане до created_at≈rdate+1день
      # (automated daily). Backfill старого date (rdate < today−2д) мав би created_at ПОЗА
      # цим вікном → dedup СЛІПИЙ → silent double-pay. Шлях наразі недосяжний (нема backfill-
      # UI), але tripwire перетворює майбутню silent-стелю на гучний fail ДО появи backfill.
      # `<=` (не `<`): dedup-вікно [rdate, rdate+2д) ВИКЛЮЧАЄ rdate+2 → саме на межі age=2
      # (виконання у rdate+2) created_at випадає з вікна → dedup сліпий. Межа теж небезпечна.
      if rdate.to_date <= 2.days.ago.to_date
        raise "ARCH.64#2: stale reward_date #{rdate} (≥2д тому) поза dedup-safe-вікном — " \
              "backfill потребує розширеного dedup-вікна (00_07 ARCH.64), інакше double-pay ризик"
      end

      BlockchainTransaction
        .where(sourceable: @cluster, token_type: :cusd, blockchain_network: "celo", reward_date: rdate)
        .where(status: [ :pending, :processing, :sent, :confirmed, :manual_review ])
        .where(created_at: rdate.beginning_of_day...(rdate + 2.days).beginning_of_day)
        .exists?
    end

    # [ARCH.50] Durable `:pending` intent ПЕРЕД broadcast (sourceable: cluster, reward_date:
    # logical day). tx_hash проставить mark_as_sent! ПІСЛЯ broadcast.
    # [ARCH.84] `insight:` — kwarg БЕЗ дефолту свідомо: підпис мусить нести вимір, і
    # забута проводка має падати гучно, а не друкувати рядок без підстави.
    def create_reward_intent!(recipient, insight:)
      BlockchainTransaction.create!(
        cluster: @cluster,
        sourceable: @cluster,
        to_address: recipient,
        amount: REWARD_AMOUNT,
        token_type: :cusd,
        blockchain_network: "celo",
        reward_date: reward_date_value,
        status: :pending,
        # `format` свідомо: колонка `numeric` → BigDecimal, а його `to_s` дав би
        # інженерний запис (`0.05e0`) просто в підписі грошового рядка.
        notes: "🌿 Celo ReFi: #{REWARD_AMOUNT} cUSD, кластер #{@cluster.name} (#{@target_date}). " \
               "stress_index #{format('%.3f', insight.stress_index)}, #{coverage_note(insight)}."
      )
    end

    # [ARCH.84] ⚖️ Присуд founder: покриття виплату НЕ гейтує — часткове покриття є
    # НОРМОЮ duty-cycled заліза (гейт на нього дав би перманентний critical майже на
    # кожному кластері), а тиша окремого дерева вже має власний шлях зі СВОЇМ машинним
    # resolve. Тому лік тут — зрізати ЗАЯВУ до виміряного: доти рядок звався «за
    # ідеальне здоров'я кластера», тоді як `stress_index` рахується лише по тих
    # деревах, що заговорили, — кластер, де з пʼяти озвалось одне, підписувався так
    # само, як виміряний повністю. ⛔ Порожнє покриття не друкуємо числом: «не
    # записано» і «виміряно нуль» — різні твердження.
    def coverage_note(insight)
      measured = insight.measured_trees
      total = insight.total_trees
      return "покриття не записано" if measured.blank? || total.blank?

      "виміряно #{measured}/#{total} дерев"
    end

    # [ARCH.50] Розрізняє збій `transact` — критично проти #4 (shared celo_cusd breaker
    # blast-radius) та #7 (reset-trap: CeloRewardWorker INCLUDE-ить Web3CircuitBreaker).
    def handle_transact_failure(intent, error)
      # intent==nil → виняток ДО створення intent (setup/balance) → нічого не broadcast.
      raise error if intent.nil?

      msg = "#{error.message} #{error.cause&.message}".downcase

      if msg.match?(REJECTED_PATTERNS)
        # Node відхилив tx (НЕ в мемпулі) → fail intent (re-payable). НЕ re-raise: детермінований
        # RpcError (`< IOError`) інакше рахується shared-breaker'ом і відкриває його (#4).
        # `if status_pending?` — intent тут завжди :pending (свіжо-створений перед transact;
        # nil відсіяно вище); guard захищає fail! від нелегального AASM-переходу, else dead (§B.4 leave).
        intent.fail!("Celo rejected: #{error.message}".truncate(500)) if intent.status_pending?
        Rails.logger.error "🛑 [Celo ReFi] Tx відхилено мережею (intent ##{intent.id} → :failed, re-payable): #{error.message}"
        nil
      elsif msg.match?(AMBIGUOUS_PATTERNS)
        # Tx із цим nonce вже подавався → попередня спроба МОГЛА broadcast → AMBIGUOUS.
        # Лишаємо intent `:pending` (dedup блокує re-pay); стале :pending → ARCH.64
        # CeloRewardReconcileWorker → :manual_review. НЕ re-raise.
        Rails.logger.warn "⚠️ [Celo ReFi] Ambiguous tx-стан (intent ##{intent.id} :pending — можливо-landed, без re-pay): #{error.message}"
        nil
      else
        # Справжній transient transport (timeout/connection) → intent `:pending` (dedup блокує
        # re-pay), re-raise → breaker рахує реальний transport + Sidekiq retry → dedup-skip.
        # Стале :pending (retry не досяг :sent) підбирає ARCH.64 CeloRewardReconcileWorker → :manual_review.
        raise error
      end
    end
  end
end
