# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "eth"
require "bigdecimal"

class BlockchainMintingService < ApplicationService
  # [HYBRID PROTOCOL GAIA]: Dynamic Minting Tax для фінансування DAO Treasury / Parametric Insurance Pool.
  # 2% від кожного карбонового мінтингу направляється до DAO Treasury, якщо страховий пул потребує фінансування.
  # [S6.17]: Ставка тепер читається з SystemParameter (governance-aware, synced from on-chain ProtocolParameters.sol).
  DEFAULT_DYNAMIC_TAX_RATE = BigDecimal("0.02")

  # [B-05 FIX]: Цільовий поріг балансу DAO Treasury (у токенах SCC).
  # Якщо баланс DAO Treasury < порогу — Dynamic Tax активний (2% від емісії).
  # Якщо баланс >= порогу — податок вимикається, інвестори отримують 100%.
  # [S6.17]: Поріг тепер читається з SystemParameter (governance-aware).
  DEFAULT_INSURANCE_POOL_THRESHOLD = 100_000

  WEI_MULTIPLIER = 10**18

  # [ARCH.62] One-Home Kredis-прапор money-path circuit-break, per-token (детекція per token_type
  # → відповідь per token_type: SFC-сплеск не гальмує SCC). Treasury::MonitorService детектор
  # ставить його при аномальному обсязі мінту (лише коли поріг + kill-switch увімкнено); цей
  # сервіс читає його per token-group. Ключ живе тут (money-core), monitor його реферує.
  MINT_CIRCUIT_FLAG_PREFIX = "mint:circuit_broken:"

  # Кеш-ключ та TTL для on-chain балансу DAO Treasury (balanceOf через Web3::Erc20Reader).
  # 15 хв — стан пулу змінюється рідко (лише при страхових виплатах); RPC ≤ 4/год замість тисяч.
  # [One-Home] той самий ключ читає Insurance::ReserveGate → один RPC на вікно на обидві фічі.
  TREASURY_BALANCE_CACHE_KEY = "dao_treasury_balance_wei"
  TREASURY_CACHE_TTL = 15.minutes
  TREASURY_RPC_TIMEOUT = 10

  # [ARCH.106] Авто-релізний TTL локу підписанта. Число мусить ПЕРЕКРИВАТИ
  # задокументований worst case батча — інакше лок відпускається, поки холдер ще
  # працює, і повертає рівно той double-mint, заради якого його й підіймали з 30 с.
  # Розклад worst case живе на місці виклику (dry-run + binary-search + fallback
  # individual mints ≈ 130 с); тут — він плюс запас на RPC-джитер.
  MINT_LOCK_TTL = 180.seconds

  # ABI оновлено для підтримки поштучного mint та пакетного batchMint.
  # [E.60 Фаза 1б] +archiveRoot (bytes32): Merkle-корінь архів-батчу телеметрії
  # (mint-anchored witness; zero32 = «без witness-клейму»). СПІЛЬНИЙ для SCC і
  # SFC (симетричні контракти — founder-рішення, жодних per-token ABI-гілок).
  CONTRACT_ABI = [
    {
      "inputs" => [
        { "internalType" => "address", "name" => "to", "type" => "address" },
        { "internalType" => "uint256", "name" => "amount", "type" => "uint256" },
        { "internalType" => "string", "name" => "identifier", "type" => "string" },
        { "internalType" => "bytes32", "name" => "archiveRoot", "type" => "bytes32" }
      ],
      "name" => "mint", "outputs" => [], "stateMutability" => "nonpayable", "type" => "function"
    },
    {
      "inputs" => [
        { "internalType" => "address[]", "name" => "recipients", "type" => "address[]" },
        { "internalType" => "uint256[]", "name" => "amounts", "type" => "uint256[]" },
        { "internalType" => "string[]", "name" => "treeDids", "type" => "string[]" },
        { "internalType" => "bytes32", "name" => "archiveRoot", "type" => "bytes32" }
      ],
      "name" => "batchMint", "outputs" => [], "stateMutability" => "nonpayable", "type" => "function"
    }
  ].to_json

  # Поштучний виклик — делегується через ApplicationService.call → new.perform
  def self.call(blockchain_transaction_id, telemetry_log: nil, created_at_span: nil)
    new([ blockchain_transaction_id ], telemetry_log: telemetry_log, created_at_span: created_at_span).perform
  end

  # Пакетний виклик для цілого сектора/кластера
  def self.call_batch(blockchain_transaction_ids, telemetry_log: nil, created_at_span: nil)
    new(blockchain_transaction_ids, telemetry_log: telemetry_log, created_at_span: created_at_span).perform
  end

  # [S6.16] `created_at_span` — партиційна підказка, НЕ фільтр: викликач передає
  # `created_at` тих самих рядків, чиї id передає, тож множина не змінюється (див.
  # `BlockchainTransaction.where_ids_pruned`). Опційний свідомо — не кожен викликач
  # тримає записи в руках; хто не передає, той обліковується лічильником degraded
  # path, а не мовчить. Це ЛІЙКА всіх мінт-шляхів, тож саме тут звуження коштує
  # найдешевше й діє на всі гілки одразу.
  def initialize(transaction_ids, telemetry_log: nil, created_at_span: nil)
    @transactions = BlockchainTransaction
                      .where_ids_pruned(transaction_ids, created_at_span, metric_caller: "BlockchainMintingService")
                      .where.not(status: :confirmed)
    @wallet_mapping = @transactions.includes(wallet: [ :tree, :organization ]).index_by(&:id)
    @telemetry_log = telemetry_log
  end

  def perform
    return if @transactions.empty?

    # [TRUSTLESS]: Перевірка децентралізованої верифікації перед мінтингом.
    # Guard clauses активні лише коли telemetry_log передано (oracle-driven flow).
    # TokenomicsEvaluatorWorker працює без telemetry_log — конвертує накопичені
    # growth_points. УВАГА: credit! зараховує бали ДО/паралельно verify (НЕ
    # downstream від IoTeX→Chainlink), тож tokenomics-шлях = оптимістичний мінт;
    # anti-fraud = ex-post clawback, не цей gate (trust-model: 05_02 §Модель
    # довіри + 00_07 ARCH.53).
    if @telemetry_log
      raise "Security Breach: Data not verified by IoTeX" unless @telemetry_log.verified_by_iotex?
      raise "Security Breach: Chainlink Oracle consensus not fulfilled" unless @telemetry_log.oracle_status_fulfilled?
    else
      # [ARCH.53]: tokenomics flow мінтить БЕЗ oracle-gate — оптимістичний мінт на
      # накопичених growth_points; anti-fraud = ex-post clawback, не цей gate.
      Rails.logger.info "📊 [Tokenomics] Batch minting без telemetry_log — " \
                        "оптимістичний мінт на накопичених growth_points (anti-fraud=clawback)."
    end

    # [RWA COMPLIANCE]: Перевірка Hadron KYC для кожного гаманця-отримувача.
    # Інституційні токени (SCC/SFC) мінтяться ТІЛЬКИ для верифікованих гаманців.
    # [S2 FIX] Non-approved / no-wallet → per-tx SKIP (НЕ raise на весь батч, дзеркало SEC.13
    # peaq-skip нижче + DOC.7 PATH 2 «silently skips if any fails»). Голий raise валив УВЕСЬ
    # pending-пул через один непройдений KYC-гаманець → retries_exhausted → нескопований
    # MintingRollbackService відкочував до 1000 ЧУЖИХ pending tx щогодини. Skipped tx лишаються
    # :pending (guard ПЕРЕД :processing) → чекають на KYC, решта батчу мінтиться.
    missing_wallet = @wallet_mapping.select { |_id, tx| tx.wallet.nil? }
    if missing_wallet.any?
      Rails.logger.error "🛑 [Compliance] Mint skipped for #{missing_wallet.size} tx без wallet."
      missing_wallet.each_key { |id| @wallet_mapping.delete(id) }
    end

    # [KYC.1] Гейт = статус БЕНЕФІЦІАРА адреси (власний АБО успадкований від
    # custodial-організації — Wallet#kyc_approved_for_minting?).
    unapproved = @wallet_mapping.select { |_id, tx| !tx.wallet.kyc_approved_for_minting? }
    if unapproved.any?
      Rails.logger.warn "🚫 [Compliance] Mint skipped for #{unapproved.size} non-Hadron-KYC-approved wallet(s)."
      unapproved.each_key { |id| @wallet_mapping.delete(id) }
    end
    return if @wallet_mapping.empty?

    # [SEC.13]: Skip minting for trees flagged `peaq_did_compromised` (emergency
    # revocation runbook, 06_04 §5.4) — a forged peaq signing key could mint for a
    # fake DID. SKIP (not raise) so one compromised tree never aborts the whole
    # batch; the rest mints normally. Org/cluster txs (no tree) are never flagged.
    # `tx.wallet&.` else dead: wallet-nil txs уже вилучені вище (missing_wallet-фільтр) →
    # тут wallet non-nil; `&.` = defensive-дубль (Wallet.tree теж NOT NULL) (§B.4 leave).
    compromised = @wallet_mapping.select { |_id, tx| tx.wallet&.tree&.peaq_did_compromised? }
    if compromised.any?
      Rails.logger.warn "🚫 [SEC.13] Mint skipped for #{compromised.size} peaq_did_compromised tree(s): " \
                        "#{compromised.values.filter_map { |tx| tx.wallet.tree.did }.join(', ')}"
      compromised.each_key { |id| @wallet_mapping.delete(id) }
      return if @wallet_mapping.empty?
    end

    # 1. ПІДКЛЮЧЕННЯ (The Alchemy Link) — Thread-cached RPC client
    client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
    # [E.2 ROLE SEPARATION]: Окремий ключ для MINTER_ROLE зменшує blast radius
    # при компрометації — slashing залишається під окремим ключем.
    # Легасі-fallback на спільний ORACLE_PRIVATE_KEY retired [INF.22] — ключ dedicated-only.
    # [SEC.17] Деривація живе в seam'і `Web3::OracleSigner` (один дім на 7 сервісів);
    # `LocalEnvSigner` = та сама ENV-поведінка, `KmsSigner` підміняється ТАМ, не тут.
    signer = Web3::OracleSigner.for(:minter)

    # [SAFETY]: Перевірка балансу Оракула
    # [INF.22] Threshold configurable через SystemParameter (governance-aware, 24h cache).
    min_oracle_matic = (SystemParameter.current(:oracle_min_balance_matic, default: 0.05) || 0.05).to_f
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
      raise "🚨 [Web3] Оракул НЕ ПРОВІЖИНЕНО: баланс рівно 0 — це стан НАЛАШТУВАННЯ, не вичерпання. ⛔ Не шукати витік: звір `nonce` (0 = з адреси не йшло нічого)."
    elsif balance < min_oracle_matic * (10**18)
      raise "🚨 [Web3] Баланс Оракула НИЖЧИЙ ЗА МІНІМУМ: #{balance} (поріг #{(min_oracle_matic * (10**18)).to_i}) — витрачено більше, ніж поповнено."
    end

    # 2. ГРУПУВАННЯ ЗА ТИПОМ ТОКЕНА (SCC та SFC мають різні контракти)
    # ⚡ [ANTI-N+1]: Використовуємо preloaded @wallet_mapping для уникнення повторних запитів
    @wallet_mapping.values.group_by(&:token_type).each do |token_type, txs|
      process_token_group(client, signer, token_type, txs)
    end
  end

  private

  # [ARCH.62] Per-token circuit-прапор. Fail-OPEN на Redis-збої: circuit-break — optional
  # stop-loss (default-off); блокувати легітимний mint через Redis-blip гірше за пропущену
  # аномалію (money liveness > optional safety, дзеркало E.46).
  def mint_circuit_broken?(token_type)
    Kredis.flag("#{MINT_CIRCUIT_FLAG_PREFIX}#{token_type}").marked?
  rescue StandardError => e
    Rails.logger.error "🛑 [ARCH.62] circuit-flag read failed (fail-open, mint proceeds): #{e.message}"
    false
  end

  def process_token_group(client, signer, token_type, txs)
    # [ARCH.62] Circuit-break HOLD: лишаємо txs :pending (re-runnable наступним циклом, коли
    # прапор спливе TTL) — НЕ escalate у manual_review. Той guard = ambiguous on-chain стан; тут
    # txs ще не торкались chain → escalate осиротив би чисті :pending назавжди (auto-discovery
    # сканує :pending, а may_escalate_to_review? з :manual_review = false → ручний toil).
    if mint_circuit_broken?(token_type)
      Rails.logger.warn "🛑 [ARCH.62] Mint circuit-breaker (#{token_type}) активний — " \
                        "#{txs.size} tx лишаються :pending (mint відкладено до reset/TTL-expiry)."
      return
    end

    # 🔴 [DOC-T.89, ⚖️ 2026-08-26] SFC-мінт ЗАБЛОКОВАНО до активації governance (SEC.1).
    #
    # Підстава не «ще не готово», а арифметика Governor'а — але ПЕРЕМІРЯНА, бо перша її
    # редакція пережила власний предмет: quorum рахувався від `totalSupply` ЛИШЕ до
    # [DOC-T.89] 2026-08-26. Відтоді `SilkenGovernor` бере базою immutable `QUORUM_BASE`
    # = SFC `MAX_SUPPLY` («4% — ЧИСЕЛЬНИК; база = QUORUM_BASE (стеля SFC), не totalSupply»,
    # `contracts/SilkenGovernor.sol`), тож кворум є 4 000 000 SFC НЕЗАЛЕЖНО від обігу, і
    # «перші 10k = 100% голосів» спростовано ТИМ САМИМ рішенням, що поставило цей гард.
    #
    # 🔴 Гард вистояв, упала його ПІДСТАВА — і небезпека вціліла, лише вужча:
    # `proposalThreshold` лишається АБСОЛЮТНИМ `10_000e18` (він і Є 0.01% стелі), тож
    # ПЕРШІ `10_000 SFC`, кому б вони не дістались, дають власникові ОДНООСІБНЕ ПРАВО
    # ПОДАВАТИ пропозиції — пройти кворум самотужки він не може. Мінт ще й авто-делегує
    # голос, тож вага виникає без жодної дії отримувача.
    #
    # 🔴 Живих writer'ів `forest_coin` у дереві сьогодні НУЛЬ — страхова виплата була
    # останнім, і її знято ТИМ САМИМ заходом DOC-T.89 (енум `ParametricInsurance`
    # звужено до `{ carbon_coin: 0 }`, значення 1 зарезервоване). Тобто гард стереже
    # не наявний шлях, а МАЙБУТНІЙ: перший же writer роздав би голоси за збиток або
    # за ріст, без Dynamic Tax і без можливості зняття (бекенд-slash SFC не існує —
    # `00_07` BIZ.14). ⚠️ Доти цей блок називав страхову виплату ЖИВИМ writer'ом —
    # той самий прохід, що поставив гард, і прибрав writer'а.
    #
    # ⚖️ Гард ЗВОРОТНИЙ і нічого не фіксує: він не обирає курс емісії, не роздає
    # allocation і не суперечить ⛔ «не фіксувати до securities-розв'язки» — він лише
    # тримає supply на нулі, доки Safe/Timelock не на місці. Знімається разом із
    # `SEC.1`-деплоєм, тим самим заходом, що вмикає governance.
    # ⛔ Не «полагодити» через ENV — це присуд, а не конфіг; зняття = редагування ЦЬОГО
    # блоку разом із записом у `00_07` DOC-T.89.
    if token_type == "forest_coin"
      Rails.logger.warn "🛑 [DOC-T.89] SFC-мінт заблоковано до активації governance (SEC.1): " \
                        "#{txs.size} tx лишаються :pending. Перші 10k SFC = одноосібне право пропозиції."
      return
    end

    contract_address = case token_type
    when "carbon_coin" then ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")
    # [DOC-T.89 §B.4 leave] Гард вище повертає ДО цієї точки, тож гілка недосяжна й
    # лишається непокритою свідомо: `04_06 §B.4` велить financial-safety-defensive
    # лишати з поясненням, а не оживляти `send`-піном заради відсотка. Знімати НЕ можна —
    # у день SEC.1 вона знадобиться, і `else raise ArgumentError` до того часу тримає
    # SFC гучно. Ліхтар на подію: hold-пін ("тримає SFC-мінт") почервоніє в мить зняття
    # гарда — грепай DOC-T.89, щоб зняти обидва надгробки одним комітом.
    when "forest_coin" then ENV.fetch("FOREST_COIN_CONTRACT_ADDRESS")
    else raise ArgumentError, "Невідомий тип токена: #{token_type}"
    end

    contract = Eth::Contract.from_abi(name: "SilkenCoin", address: contract_address, abi: CONTRACT_ABI)
    lock_key = "lock:web3:oracle:#{signer.address}"

    # [E.60 Фаза 1б] Архів-групування: ПІСЛЯ KYC/SEC.13-фільтрів (perform) і
    # circuit-check (вище), ПОЗА oracle-локом (побудова = SELECT + sha256;
    # стемпінг/пін — async у pin-воркері; НІКОЛИ не носити це під 120s-бюджет
    # локу). Один transact-виклик = один root фізично → цикл per-підгрупою;
    # свіжий диспатч = усі tx у nil-групі → 1 батч → 1 виклик (без gas-регресу).
    archive_groups = Mrv::TelemetryArchiveBatchService.group(
      txs, token_type: token_type,
      # [DOC-T.89] ОБИДВІ половини умови, через One-Home `taxing?` — той самий предикат,
      # що й у `build_batch_arrays`. Доти тут стояв лише ТИП, тож при повному пулі поле
      # `tax_rate_applied` артефакту стверджувало ставку, якої не стягували.
      tax_rate: taxing?(token_type) ? dynamic_tax_rate : nil
    )

    # [OBSERVABILITY]: every tx we commit to minting counts as an attempt — the
    # SLO denominator (success = MINT_SUCCESS_TOTAL on status→sent). Counted before
    # the lock so lock-timeout / RPC-outage failures still land in the ratio.
    txs.each { SilkenNet::Metrics::MINT_ATTEMPTS_TOTAL.increment(labels: { token_type: token_type }) }

    # [E.60] Rescue живе ПЕР-ПІДГРУПОЮ (усередині
    # dispatch_archive_group): збій пізньої підгрупи НЕ торкається tx уже-sent
    # ранніх (старий group-wide rescue ескалював би здорові :sent у manual_review,
    # а retry сліпо re-мінтив би їх = double-mint). safe_fail якоїсь підгрупи
    # re-raise'иться ПІСЛЯ проходу всіх груп; safe-failed tx одужують через
    # СВІЖІ tokenomics-tx (усі growth-викликачі переобирають лише :pending),
    # retry-сигнал лише повертає джоб у чергу; sent/manual_review захищені
    # dispatchable-фільтром у dispatch.
    safe_fail_error = nil
    begin
      # [S6.5 FIX]: Збільшено lock timeout з 30s до 120s для batch operations.
      # Хоча ми не чекаємо підтвердження блоку (fire-and-forget), batch minting може включати:
      #   - Dry-run eth_call (~3-5s)
      #   - Binary Search Isolation при revert: до MAX_BINARY_SEARCH_DEPTH=6 рівнів × 2 eth_call = ~36s
      #   - Fallback individual mints для poisoned records: до ~30 × transact() = ~90s
      # Загальний worst case: ~130s. З 30s lock виникає double-mint ризик при RPC congestion.
      # 🔴 [ARCH.106] Доти тут стояло `120.seconds` — МЕНШЕ за власний worst case
      # рядком вище, тобто лок авто-відпускався за ~10 с до кінця найдовшого
      # легального проходу й пускав другого воркера на того самого підписанта.
      # Дефект був невидимий, бо число й розрахунок стояли поруч і обидва
      # виглядали обдуманими; TTL тепер константа, що ПЕРЕКРИВАЄ розрахунок.
      Kredis.lock(lock_key, expires_in: MINT_LOCK_TTL, after_timeout: :raise) do
        archive_groups.each do |group|
          safe_fail_error ||= dispatch_archive_group(client, contract, signer, token_type, group)
        end
      end
    rescue Kredis::LockTimeout => e
      # Лок не взято — ЦЕЙ джоб нічого не бродкастив. АЛЕ in-memory статуси
      # можуть бути stale: конкурентний джоб (той, що тримав лок >120s) міг уже
      # змінтити спільні tx → пере-читання + той самий sent/manual_review-guard, що й
      # у dispatch (сліпий fail! клоберив би :sent → release locked_points при
      # токенах on-chain = double-credit; lock_version на партиційованій таблиці
      # немає — optimistic-lock не рятує).
      # [S6.16] Пере-читання — через One-Home: голий `.reload` б'є по самому PK і
      # сканує ВСІ партиції, хоч `created_at` уже в пам'яті з SELECT'а. Прецедент
      # форми — CeloRewardReconcileWorker.
      txs.each do |tx|
        fresh = BlockchainTransaction.find_with_partition_pruning(tx.id, tx.created_at)
        next if fresh.status_sent? || fresh.status_manual_review? || fresh.status_confirmed?

        fresh.fail!(e.message.truncate(200))
      end
      Rails.logger.error "🛑 [Web3 Failure] Lock timeout (#{token_type}): #{e.message}"
      raise e
    end

    raise safe_fail_error if safe_fail_error
  end

  # [E.60 Фаза 1б] Диспатч однієї архів-підгрупи: єдиний transact несе ЇЇ root
  # (N:1 — bisect/individual-гілки теж). Фіналізація per-групою ОДРАЗУ після
  # broadcast (прецедент — send_clean_batch у тому ж локу). Повертає safe_fail-
  # помилку для re-raise (Sidekiq-retry) або nil (успіх / ambiguous-ескалація).
  def dispatch_archive_group(client, contract, signer, token_type, group)
    # Диспатчабельні = НЕ sent/manual_review/processing: retry після часткової
    # multi-групової відмови (і direct .call на recovered-orphan) НЕ сміє сліпо
    # флипати їх у :processing — обхід double-spend hold. :processing-orphan
    # (crash між transact і mark_as_sent) — справа sweeper'а (escalate за 15хв),
    # не сліпого re-mint'а.
    txs = group.txs.reject { |tx| tx.status_sent? || tx.status_manual_review? || tx.status_processing? }
    skipped = group.txs.size - txs.size
    if skipped.positive?
      Rails.logger.warn "🚫 [Web3] #{skipped} tx підгрупи в sent/manual_review/processing — skip (double-mint guard)."
    end
    return nil if txs.empty?

    root_arg = bytes32_arg(group.root)

    # Переводимо транзакції підгрупи в статус обробки
    txs.each do |tx|
      tx.update!(status: :processing)
    end

    if txs.size == 1
      # Одиночний мінтинг (Fire-and-Forget): root ПІДГРУПИ — для генуїнно-1-tx
      # батчу бітово = telemetry_merkle_root; після dispatchable-відсіву сусідів
      # одинак далі несе batch-root (N:1); ZERO_ROOT для windowless —
      # insurance/celo/burn мінти чесно їдуть «без witness-клейму».
      # [ВИПРАВЛЕНО]: Використовуємо transact ЗАМІСТЬ transact_and_wait
      tx = txs.first
      tx_hash = signer.transact(
        client, contract, "mint", tx.to_address, to_wei(tx.amount), identifier_for(tx), root_arg,
        legacy: false
      )
      finalize_sent_transaction(tx, tx_hash, token_type)
      Rails.logger.info "🛰️ [Web3] Одиночний мінт у мемпулі. TX: #{tx_hash}"
    else
      # 💎 ПАКЕТНИЙ МІНТИНГ (Gas Saving Mode)
      # [HYBRID PROTOCOL GAIA]: Для carbon_coin при недофінансованому страховому пулі
      # застосовується Dynamic Tax — 2% від суми кожної транзакції до DAO Treasury.
      recipients, amounts, identifiers, tax_total = build_batch_arrays(txs, token_type)

      Rails.logger.info "📦 [Web3] BatchMinting #{txs.size} транзакцій для #{token_type} " \
                        "(root #{group.root[0, 12]}…)..."

      # [DRY-RUN GUARD]: eth_call-симуляція ловить "отруйний" запис ДО витрати газу;
      # [BINARY SEARCH]: при revert — ізоляція отруйних У МЕЖАХ підгрупи (halves
      # не страдлять межі батчів — E.60 інваріант «один виклик = один root»).
      if batch_dry_run_reverts?(client, contract, signer, recipients, amounts, identifiers, root_arg)
        Rails.logger.warn "⚠️ [Web3] batchMint dry-run reverted. Binary search isolation for #{txs.size} txs..."
        fallback_to_individual_mints(client, contract, signer, token_type, txs, root_arg)
      else
        tx_hash = signer.transact(
          client, contract, "batchMint", recipients, amounts, identifiers, root_arg,
          legacy: false
        )
        # [ARCH.52] earliest батч-created_at → ConfirmationWorker partition-prune
        # (батч ділить один tx_hash; спільний confirm_at → unique_for дедуплікує до 1).
        # [DOC-T.89] Податок лічимо ПІСЛЯ broadcast — саме те, що реально полетіло.
        SilkenNet::Metrics::TAX_COLLECTED_TOTAL.increment(by: tax_total.to_f, labels: { token_type: }) if tax_total.to_f.positive?
        batch_confirm_at = txs.min_by(&:created_at).created_at
        txs.each { |tx| finalize_sent_transaction(tx, tx_hash, token_type, batch_confirm_at) }
        Rails.logger.info "🛰️ [Web3] Пакет відправлено в мемпул. TX: #{tx_hash}"
      end
    end
    nil
  rescue StandardError => e
    # [P0-1/M6] Стан-обізнаний rescue ЦІЄЇ підгрупи (дзеркало
    # send_clean_batch M6 + burn ARCH.48) — сусідні підгрупи недоторкані:
    #   :sent (finalize-крах ПІСЛЯ mark_as_sent У ЦІЙ групі) → escalate, НЕ fail!;
    #   pre-broadcast transact-error (revert/insufficient) → tx НЕ полетіла →
    #     безпечний fail! + return e (caller re-raise → Sidekiq retry перемінтить);
    #   ambiguous (timeout/connection ПІСЛЯ можливого broadcast) → escalate
    #     manual_review, БЕЗ retry (сліпий re-mint = double).
    # KeyError (ENV-конфіг: DAO_TREASURY_ADDRESS тощо) = ДО transact гарантовано →
    # safe fail!+retry, не хибний manual_review-toil на конфіг-баг.
    safe_fail = e.is_a?(KeyError) || transact_error_pre_broadcast?(e)
    # escalate без may-гарда легальний: dispatchable-фільтр + processing-флип
    # гарантують from-стан :sent/:processing (обидва в дозволених для escalate).
    txs.each do |tx|
      if tx.status_sent?
        tx.escalate_to_review!("Крах після broadcast — звір Polygonscan ПЕРЕД re-mint: #{e.message}")
      elsif safe_fail
        tx.fail!(e.message.truncate(200))
      else
        tx.escalate_to_review!("Ambiguous mint broadcast — звір Polygonscan ПЕРЕД re-mint: #{e.message}")
      end
    end
    Rails.logger.error "🛑 [Web3 Failure] Підгрупа (root #{group.root[0, 12]}…) впала " \
                       "(#{safe_fail ? 'pre-broadcast' : 'AMBIGUOUS→manual_review'}): #{e.message}"
    safe_fail ? e : nil
  end

  # [E.60] hex-root → bytes32-аргумент eth.rb: "0x"-префікс без padding
  # (прецедент Ethereum::StateAnchorService#anchor_to_l1! root_bytes).
  def bytes32_arg(root_hex)
    "0x#{root_hex}"
  end

  # [DRY-RUN GUARD]: Симуляція batchMint через eth_call (zero-gas execution).
  # eth_call виконує код контракту на поточному блоці без створення транзакції.
  # Повертає true, якщо симуляція завершилась revert (батч містить "отруйний" запис).
  # При помилці підключення — повертає false (оптимістичний фолбек: спробувати transact).
  def batch_dry_run_reverts?(client, contract, signer, recipients, amounts, identifiers, root_arg)
    signer.static_call(client, contract, "batchMint", recipients, amounts, identifiers, root_arg)
    false
  rescue StandardError => e
    Rails.logger.warn "⚠️ [Web3] batchMint dry-run помилка: #{e.message}"
    # Розрізняємо EVM revert (контракт відхилив) від мережевих помилок (RPC timeout)
    evm_revert?(e)
  end

  # Визначає, чи помилка є EVM revert (контракт відхилив виконання).
  # Мережеві помилки (timeout, connection refused) не рахуються як revert.
  def evm_revert?(error)
    message = error.message.to_s.downcase
    message.include?("revert") || message.include?("execution reverted") || message.include?("out of gas")
  end

  # =========================================================================
  # 🔍 BINARY SEARCH POISONED RECORD ISOLATION (Divide & Conquer)
  # =========================================================================
  # Замість наївного fallback на N окремих mint() транзакцій при збої batchMint,
  # використовуємо бінарний пошук через безкоштовні eth_call dry-run для ізоляції
  # "отруйних" записів. Типовий сценарій (1-2 отруйних з 100) вирішується за
  # ~14 eth_call + 2-3 batchMint замість 100 окремих mint().
  #
  # Обмеження:
  #   - MIN_BINARY_SEARCH_SIZE (4): підбатчі менше цього → індивідуальні mints
  #   - MAX_BINARY_SEARCH_DEPTH (6): запобігає нескінченній рекурсії (~2^6 = 64 мін. елементів)
  #   - Poisoned ratio guard: якщо >30% батча отруйні → fallback на індивідуальні mints
  # =========================================================================

  # Мінімальний розмір підбатча для binary search. Менші батчі мінтяться поштучно.
  MIN_BINARY_SEARCH_SIZE = 4

  # Максимальна глибина рекурсії binary search (запобігає нескінченному поділу).
  MAX_BINARY_SEARCH_DEPTH = 6

  # Поріг "отруйності" — якщо більше 30% транзакцій отруйні, binary search неефективний.
  POISONED_RATIO_THRESHOLD = 0.3

  # [FALLBACK]: Ізоляція "отруйних" записів через бінарний пошук (Divide & Conquer).
  # Якщо batchMint dry-run впав, розбиваємо батч навпіл і тестуємо кожну половину.
  # "Чисті" половини відправляються через batchMint, "отруйні" — далі діляться.
  # Результат: 99 з 100 транзакцій відправляються 1-2 batchMint, 1 отруйна — mint().
  # [E.60] root_arg = root архів-підгрупи: усі sub-batch'і та individual-мінти
  # одного диспатчу несуть ТОЙ САМИЙ root (N:1 — root свідчить evidence-набір
  # диспатчу, не 1:1 композицію мінта; канон 05_02 §E.60).
  def fallback_to_individual_mints(client, contract, signer, token_type, txs, root_arg)
    poisoned = []
    clean = []
    original_batch_size = txs.size

    # Запускаємо бінарний пошук для ізоляції отруйних записів
    isolate_poisoned_records(client, contract, signer, token_type, txs, poisoned, clean,
                             root_arg, depth: 0, original_batch_size: original_batch_size)

    Rails.logger.info "🔍 [Web3] Binary search result: #{clean.size} clean, #{poisoned.size} poisoned out of #{original_batch_size}"

    # Відправляємо "чисті" транзакції оптимальними батчами
    clean.each_slice(Treasury::MintBatchCollectorService::OPTIMAL_BATCH_SIZE) do |batch|
      send_clean_batch(client, contract, signer, token_type, batch, root_arg)
    end

    # Мінтимо "отруйні" транзакції поштучно (вони, ймовірно, впадуть)
    poisoned.each do |tx|
      mint_individual(client, contract, signer, token_type, tx, root_arg)
    end

    # Повертаємо nil — всі транзакції вже оброблені
    nil
  end

  # Рекурсивний бінарний пошук для ізоляції отруйних записів.
  # Кожен рівень рекурсії ділить батч навпіл і тестує через eth_call dry-run.
  def isolate_poisoned_records(client, contract, signer, token_type, txs, poisoned, clean, root_arg, depth:, original_batch_size:)
    # Базовий випадок: батч занадто малий або досягнуто максимальної глибини — мінтимо поштучно
    if txs.size < MIN_BINARY_SEARCH_SIZE || depth >= MAX_BINARY_SEARCH_DEPTH
      Rails.logger.info "🔍 [Web3] Binary search: #{txs.size} txs at depth=#{depth} below threshold, marking as potentially poisoned"
      txs.each { |tx| poisoned << tx }
      return
    end

    # Перевіряємо, чи ще ефективний binary search (>30% від оригінального батча отруйні — fallback)
    if poisoned.any? && poisoned.size > original_batch_size * POISONED_RATIO_THRESHOLD
      Rails.logger.warn "⚠️ [Web3] Binary search: >30% poisoned (#{poisoned.size}/#{original_batch_size}). " \
                        "Fallback to individual mints for remaining #{txs.size} txs."
      txs.each { |tx| poisoned << tx }
      return
    end

    mid = txs.size / 2
    left_half = txs[0...mid]
    right_half = txs[mid..]

    # Тестуємо ліву половину через dry-run
    process_half(client, contract, signer, token_type, left_half, poisoned, clean,
                 root_arg, depth: depth, original_batch_size: original_batch_size)

    # Тестуємо праву половину через dry-run
    process_half(client, contract, signer, token_type, right_half, poisoned, clean,
                 root_arg, depth: depth, original_batch_size: original_batch_size)
  end

  # Обробляє одну половину батча: dry-run → clean або рекурсивний поділ.
  def process_half(client, contract, signer, token_type, half_txs, poisoned, clean, root_arg, depth:, original_batch_size:)
    return if half_txs.empty?

    recipients, amounts, identifiers, = build_batch_arrays(half_txs, token_type)

    if batch_dry_run_reverts?(client, contract, signer, recipients, amounts, identifiers, root_arg)
      # Ця половина містить отруйний запис — ділимо далі
      Rails.logger.info "🔍 [Web3] Binary search depth=#{depth + 1}: sub-batch of #{half_txs.size} reverted, splitting..."
      isolate_poisoned_records(client, contract, signer, token_type, half_txs, poisoned, clean,
                               root_arg, depth: depth + 1, original_batch_size: original_batch_size)
    else
      # Ця половина чиста — додаємо до clean
      clean.concat(half_txs)
    end
  end

  # Будує масиви recipients/amounts/identifiers для підбатча (з Dynamic Tax).
  # [O2/O4 FIX] Податок агрегується в ОДИН DAO_TREASURY-запис на батч (не по одному на tx).
  # Раніше кожна оподаткована tx пушила ДВА записи (forester + treasury) → масив подвоювався,
  # а `OPTIMAL_BATCH_SIZE == on-chain MAX_BATCH_SIZE == 100`, тож carbon-батч >50 tx перевищував
  # ліміт і `batchMint` ревертив ІЗ GENESIS (податок ON при treasury<100k = стартовий стан) →
  # кожен такий батч зайво детурив через binary-search. N+1 записів ≤ 100 при N≤99 + економія газу.
  def build_batch_arrays(txs, token_type)
    recipients = []
    amounts = []
    identifiers = []
    taxing = taxing?(token_type) # [DOC-T.89] One-Home — дзеркало `tax_rate:` архів-групування
    tax_total = 0

    txs.each do |tx|
      if taxing
        tax_amount = (tx.amount * dynamic_tax_rate).round(4)
        tax_total += tax_amount
        recipients.push(tx.to_address)
        amounts.push(to_wei(tx.amount - tax_amount))
        identifiers.push(identifier_for(tx))
      else
        recipients.push(tx.to_address)
        amounts.push(to_wei(tx.amount))
        identifiers.push(identifier_for(tx))
      end
    end

    # Один агрегований treasury-запис на весь підбатч (сума всіх податків).
    if tax_total.positive?
      recipients.push(ENV.fetch("DAO_TREASURY_ADDRESS"))
      amounts.push(to_wei(tax_total))
      identifiers.push("#{TAX_BATCH_PREFIX}#{identifier_for(txs.first)}")
    end

    # [DOC-T.89] `tax_total` віддається НАЗОВНІ, а не інкрементується тут: цей метод
    # біжить на КОЖНОМУ рівні бінарного пошуку (`process_half`), тож лічильник усередині
    # рахував би той самий податок 2–14 разів при жодному реальному broadcast'і.
    [ recipients, amounts, identifiers, tax_total ]
  end

  # Відправляє "чистий" батч через batchMint (або mint для одиночних).
  def send_clean_batch(client, contract, signer, token_type, txs, root_arg)
    return if txs.empty?

    if txs.size == 1
      mint_individual(client, contract, signer, token_type, txs.first, root_arg)
      return
    end

    recipients, amounts, identifiers, tax_total = build_batch_arrays(txs, token_type)

    tx_hash = signer.transact(
      client, contract, "batchMint", recipients, amounts, identifiers, root_arg,
      legacy: false
    )

    # [ARCH.52] Спільний earliest created_at → усі finalize шлють ІДЕНТИЧНІ ConfirmationWorker-args
    # на спільний batchMint tx_hash → unique_for дедуплікує до 1 воркера (не N).
    # [DOC-T.89] Податок лічимо ПІСЛЯ broadcast — саме те, що реально полетіло.
    SilkenNet::Metrics::TAX_COLLECTED_TOTAL.increment(by: tax_total.to_f, labels: { token_type: }) if tax_total.to_f.positive?
    batch_confirm_at = txs.min_by(&:created_at).created_at
    txs.each { |tx| finalize_sent_transaction(tx, tx_hash, token_type, batch_confirm_at) }

    Rails.logger.info "✅ [Web3] Clean sub-batch of #{txs.size} sent via batchMint. TX: #{tx_hash}"
  rescue StandardError => e
    # [M6/ARCH.45] Розрізняємо збій ДО vs ПІСЛЯ broadcast (дзеркало ARCH.48 3-case для burn).
    # EVM revert = tx НЕ полетіла (rare dry-run race) → безпечний individual-fallback. Мережева
    # помилка (timeout/connection) = batchMint МІГ полетіти в мемпул до втрати відповіді →
    # сліпий individual re-mint = DOUBLE-MINT. Ескалюємо у manual_review (звір Polygonscan), НЕ
    # re-mint наосліп. txs тут у :processing (переведені перед dry-run) → escalate легальний.
    if transact_error_pre_broadcast?(e)
      Rails.logger.error "🛑 [Web3] Clean batch pre-broadcast fail (#{txs.size} txs): #{e.message}. Individual fallback."
      txs.each { |tx| mint_individual(client, contract, signer, token_type, tx, root_arg) }
    else
      Rails.logger.error "🛑 [Web3] Clean batch AMBIGUOUS broadcast (#{txs.size} txs): #{e.message}. " \
                         "→ manual_review (no blind re-mint — batchMint міг landed)."
      txs.each do |tx|
        tx.escalate_to_review!("batchMint ambiguous broadcast — звір Polygonscan ПЕРЕД re-mint: #{e.message}") if tx.may_escalate_to_review?
      end
    end
  end

  # [M6/ARCH.45] Чи означає помилка transact, що tx ТОЧНО НЕ полетіла в мемпул (безпечно re-mint /
  # fail). Лише коли вузол ВІДХИЛИВ tx до включення: EVM revert (executed+reverted / out-of-gas —
  # НЕ minted) або `insufficient funds` (oracle-balance, rejected). Мережева невизначеність
  # (timeout/connection/EOF) → false → ambiguous → escalate.
  # [P2-4] `nonce too low` / `already known` / `replacement underpriced` НЕ pre-broadcast — вони
  # означають, що tx (наша попередня чи ця) ВЖЕ у мемпулі/блоці → сліпий individual re-mint =
  # DOUBLE-MINT → їх лишаємо ambiguous (escalate). Дзеркало burn ARCH.48.
  # 🔴 [ARCH.62, виміряно 2026-09-05] ТРЕТЯ родина, якої тут бракувало — ВАЛІДАЦІЙНА
  # відмова вузла за газ-лімітом. Amoy відповідав дослівно `Transaction gas limit is
  # too low, try 74494!`; це не збігалося з жодним патерном вище, тож детермінована
  # відмова ДО броадкасту їхала як `ambiguous` → `escalate_to_review!`.
  # ⛔ **І це порушує власний контракт стану:** `manual_review` визначено як «tx_hash Є,
  # стан невідомий, кошти заблоковані» (`CLAUDE.md §6`, `04_01`), а тут `tx_hash = nil`
  # і в мемпулі нема нічого. Виміряна ціна — 44 мінти в лімбі з порожнім хешем.
  # ⚠️ Сесія 09-05 полагодила ПРИЧИНУ (оцінка `gas_limit` на шві `KeySigner#transact`),
  # і саме тому цей рядок лишався непоміченим: симптом зник, а класифікатор так само
  # не вміє назвати цю родину — наступний `exceeds block gas limit` дав би той самий toil.
  # ✅ Безпечно вважати pre-broadcast: вузол відкидає такий кадр на ВАЛІДАЦІЇ, до
  # прийняття в мемпул, тож re-mint не може бути double-mint. Це та сама межа, що
  # відділяє їх від `nonce too low`/`already known` вище.
  GAS_LIMIT_REJECTIONS = [ "gas limit is too low", "intrinsic gas too low", "exceeds block gas limit",
                          "gas required exceeds allowance" ].freeze

  def transact_error_pre_broadcast?(error)
    return true if evm_revert?(error)

    message = error.message.to_s.downcase
    return true if GAS_LIMIT_REJECTIONS.any? { |m| message.include?(m) }

    message.include?("insufficient funds")
  end

  # Мінтить одну транзакцію індивідуально з обробкою помилок.
  # [E.60] root_arg = root архів-підгрупи (N:1 — навіть poisoned-одинак свідчить
  # батчем, у якому диспатчився).
  def mint_individual(client, contract, signer, token_type, tx, root_arg)
    individual_tx_hash = signer.transact(
      client, contract, "mint", tx.to_address, to_wei(tx.amount), identifier_for(tx), root_arg,
      legacy: false
    )

    finalize_sent_transaction(tx, individual_tx_hash, token_type)
  rescue StandardError => e
    # [M6] Той самий double-mint guard: pre-broadcast fail → fail! (M2 звільнить locked);
    # ambiguous (mint міг landed) → manual_review, НЕ голий fail! (інакше бали звільнено, а
    # токени on-chain → наступний mint = double).
    if transact_error_pre_broadcast?(e)
      Rails.logger.error "🛑 [Web3] Individual mint failed (pre-broadcast) TX ##{tx.id}: #{e.message}"
      tx.fail!(e.message.truncate(200))
    else
      Rails.logger.error "🛑 [Web3] Individual mint AMBIGUOUS broadcast TX ##{tx.id}: #{e.message} → manual_review."
      tx.escalate_to_review!("Individual mint ambiguous broadcast — звір Polygonscan: #{e.message}") if tx.may_escalate_to_review?
    end
  end

  # Фіналізує транзакцію після успішної відправки (shared logic для batch та individual).
  # [ARCH.52] `confirm_at` = СПІЛЬНИЙ earliest created_at батчу (усі рядки ділять tx_hash) →
  # усі N finalize дають ІДЕНТИЧНІ ConfirmationWorker-args → unique_for дедуплікує до 1.
  def finalize_sent_transaction(tx, tx_hash, token_type, confirm_at = nil)
    # [ARCH.55] mark_as_sent! (AASM) проставляє sent_at — sweeper ключується на моменті broadcast.
    if @telemetry_log
      tx.chainlink_request_id = @telemetry_log.chainlink_request_id
      tx.zk_proof_ref = @telemetry_log.zk_proof_ref
    end
    tx.mark_as_sent!(tx_hash)

    # [INF.26] `by: tx.amount` — метрика зветься «tokens minted», а голий `.increment`
    # рахував ТРАНЗАКЦІЇ. Вирішує це не імʼя, а СПОЖИВАЧ: обидві серії живуть на одній
    # панелі «SCC Minted vs Slashed», на одній осі, і сусідній `SCC_SLASHED_TOTAL` уже
    # інкрементиться `by: effective_burn` — тобто графік віднімав монети від штук.
    # Моменти при цьому симетричні (обидва на broadcast, до підтвердження), тож після
    # вирівнювання одиниці порівняння стає чесним.
    SilkenNet::Metrics::SCC_MINTED_TOTAL.increment(by: tx.amount, labels: { token_type: token_type })
    # SLO numerator (06_08 §2.4) — successful broadcast (status→sent). Тут саме ПОДІЯ,
    # а не сума: знаменник `MINT_ATTEMPTS_TOTAL` теж рахує спроби.
    SilkenNet::Metrics::MINT_SUCCESS_TOTAL.increment(labels: { token_type: token_type })

    # [ARCH.52] СПІЛЬНИЙ confirm_at для batch (інакше per-tx created_at ламає unique_for → N воркерів);
    # mint_individual → confirm_at=nil → tx.created_at (унікальний tx_hash, дедуп не потрібен).
    BlockchainConfirmationWorker.perform_in(30.seconds, tx_hash, (confirm_at || tx.created_at).iso8601)
  end

  # 🔴 [DOC-T.89, ⚖️ 2026-08-26] Страхова емісія дістає ВЛАСНИЙ префікс.
  #
  # Доти `identifier_for` віддавав той самий `tree.did` і за верифікований ріст, і за
  # страховий випадок, тож зовнішній аудитор і ESG-покупець не відділяли «намінтили за
  # вимір» від «намінтили за збиток». Для `MRV.1` це гірше за незручність: lineage
  # payout-мінта веде до вимірів, яких не було.
  #
  # ✅ Споживач префікса ІСНУЄ з того ж проходу — `subgraph/src/mapping.ts` класифікує
  # подію (`mintKindOf`) і веде три лічильники з перевірним інваріантом
  # `totalMinted == totalMintedGrowth + totalMintedInsurance + totalMintedTax`.
  # ⚠️ Цей абзац доти казав «subgraph … БЕЗ гілкування» і називав серед потерпілих
  # `chain_audit_delta` — обидві половини хибні, виправлено 2026-08-28. Друга гірша за
  # першу, бо вигадувала дефект: `ChainAuditService` звіряє СУПЛАЙ (Σmint − Σburn проти
  # on-chain `totalSupply()`), і розводити там природи не треба — саме тому `totalMinted`
  # у схемі свідомо лишили сумою всіх трьох, як supply-бік тотожності з `totalBurned`.
  # Паритет літералів префіксів тримає `spec/quality/mint_prefix_parity_spec.rb` [OPS.36].
  #
  # Форма запозичена в податку (`TAX_BATCH_…`) — префікс на тому самому полі, без зміни
  # ABI. ⏳ Ціна рішення асиметрична в ЧАСІ: сьогодні нічого не задеплоєно (SEC.1
  # pending), тож це один рядок; після mainnet — міграція формату on-chain події з
  # розривом історії. Саме тому робиться ЗАРАЗ, а не «коли знадобиться».
  INSURANCE_MINT_PREFIX = "INS_"
  # Той самий клас, що `INSURANCE_MINT_PREFIX`, і доти він жив ГОЛИМ ЛІТЕРАЛОМ усередині
  # `build_batch_arrays` [OPS.36, 2026-08-27]. Ім'я потрібне не для краси: обидва префікси
  # продубльовані в `subgraph/src/mapping.ts`, а наш пін-двигун ключується на `NAME = value`
  # (§Guard-craft #97), тож незіменований літерал сидить поза БУДЬ-ЯКИМ гейтом за побудовою.
  # Паритет двох боків тепер стереже `spec/quality/mint_prefix_parity_spec.rb`.
  TAX_BATCH_PREFIX = "TAX_BATCH_"

  def identifier_for(tx)
    tree = tx.wallet&.tree
    base = if tx.token_type == "carbon_coin"
      tree&.did || "ORG_#{tx.wallet&.organization_id}"
    else
      "CLUSTER_#{tree&.cluster_id || 'GLOBAL'}"
    end
    tx.sourceable_type == "ParametricInsurance" ? "#{INSURANCE_MINT_PREFIX}#{base}" : base
  end

  def to_wei(amount)
    Web3::WeiConverter.to_wei(amount)
  end

  # [B-05 FIX]: Cached On-Chain Oracle для перевірки стану Parametric Insurance Pool.
  # Виконує eth_call balanceOf на SCC-контракті для адреси DAO Treasury.
  # Результат кешується на 15 хвилин — стан пулу змінюється рідко (лише при страхових виплатах).
  #
  # [E.46 FIX]: При збої RPC повертаємо false — не накладаємо 2% Dynamic Tax під час деградації мережі.
  # Rationale: False negative (пропущений внесок до пулу) безпечніший за false positive
  # (постійний 2% податок на кожен mint при тривалому RPC outage). Пул поповниться при
  # наступному успішному виклику. Помилка логується для моніторингу (Sentry + Prometheus).
  def insurance_pool_requires_funding?
    fetch_treasury_balance_wei < insurance_pool_threshold_wei
  rescue StandardError => e
    Rails.logger.error "🛑 [Web3] DAO Treasury balance check failed (RPC degraded): #{e.message}"
    # [E.46] Завжди false при RPC-збої — не штрафуємо мінтинг під час деградації мережі.
    false
  end

  # [DOC-T.89] ОДИН дім питання «чи цей мінт оподатковується».
  #
  # Доти умова жила у ДВОХ місцях у РІЗНИХ формах: `build_batch_arrays` питав обидві
  # половини (тип І стан пулу), а `tax_rate:`, що їде в архів-артефакт, — лише ТИП.
  # Тож коли пул повний і податку НЕ брали, `TelemetryArchiveBatch#tax_rate_applied`
  # діставав `dynamic_tax_rate` і їхав в IPFS-артефакт поруч із сумами: поле з іменем
  # «applied» казало про себе неправду. Аудитор хибної арифметики не отримував —
  # `VERIFICATION_INSTRUCTIONS` оголошують `amount` як ISSUER-ASSERTED, — але критерій
  # місії («правдиво») це не косметика.
  #
  # ⚠️ Мемоїзація тут НЕ оптимізація, а ІНВАРІАНТ. Два call-site'и читають стан пулу в
  # різні моменти тракту, а `Web3::Erc20Reader` кешує 15-хвилинним вікном — без memo
  # батч, що перетнув межу вікна, дістав би ДВІ податкові правди: суми за однією,
  # артефакт за іншою. Дзеркало `EvaluateTreeBatchWorker` («один поріг на чанк»).
  # `defined?`-форма, а не `||=`, бо легітимне значення тут — `false`.
  #
  # 🔑 Форма зберігає й майбутню безпеку, заради якої тут стояв надгробок: у день
  # зняття SFC-гарда (SEC.1) `taxing?("forest_coin")` віддає `false` СТРУКТУРНО, тож
  # carbon-ставка не може мовчки потрапити в артефакт SFC-батчу.
  def taxing?(token_type)
    return false unless token_type == "carbon_coin"
    return @taxing_carbon if defined?(@taxing_carbon)

    @taxing_carbon = insurance_pool_requires_funding?
  end

  # Баланс DAO Treasury у wei (Integer). [One-Home] через Web3::Erc20Reader зі спільним
  # cache-ключем → Insurance::ReserveGate читає той самий баланс (один RPC на 15-хв вікно).
  def fetch_treasury_balance_wei
    Web3::Erc20Reader.balance_of_wei(
      contract_env_key: "CARBON_COIN_CONTRACT_ADDRESS",
      holder: ENV.fetch("DAO_TREASURY_ADDRESS"),
      cache_key: TREASURY_BALANCE_CACHE_KEY, ttl: TREASURY_CACHE_TTL, timeout: TREASURY_RPC_TIMEOUT
    )
  end

  # [S6.17] Governance-aware Dynamic Tax Rate.
  # Reads from SystemParameter (synced from on-chain ProtocolParameters.sol via ParameterSyncWorker).
  # Falls back to DEFAULT_DYNAMIC_TAX_RATE if not set.
  #
  # 🔴 [DOC-T.89] Memo тут НЕСУЧЕ, а не «щоб не робити N+1». Читачів ДВА і вони в
  # різних кінцях диспатчу: `tax_rate:`, що їде в архів-артефакт батчу, і суми в
  # `build_batch_arrays` — причому другий біжить на КОЖНОМУ рівні бінарного пошуку.
  # Значення приходить через `SystemParameter.current`, тобто через `Rails.cache`,
  # який `after_commit` інвалідує при БУДЬ-ЯКОМУ записі параметра. Отже коміт
  # `Governance::ParameterSyncWorker` посеред диспатчу без memo дав би артефакту одну
  # ставку, а сумам іншу — той самий клас, що DOC-T.89 закрив на половині СТАНУ
  # (`taxing?`), лише тут на половині ЗАКОНУ. ⛔ Не знімати як «зайву мемоїзацію».
  def dynamic_tax_rate
    @dynamic_tax_rate ||= BigDecimal(SystemParameter.current(:dynamic_tax_rate, default: DEFAULT_DYNAMIC_TAX_RATE).to_s)
  end

  # [S6.17] Governance-aware Insurance Pool Threshold.
  #
  # ⚠️ [DOC-T.89] На відміну від сусіда вище, це memo сьогодні ІНЕРТНЕ — і різниця
  # названа явно саме тому, що обидва місця роками несли той самий коментар про N+1,
  # тож розрізнити їх з коду було ніяк. Єдиний читач іде через `taxing?`, який сам
  # мемоїзований, отже значення береться рівно раз на інстанс і без цього рядка.
  # Лишається як другий замок на тих самих дверях: перший же читач в обхід `taxing?`
  # робить його несучим, а ціна нульова.
  def insurance_pool_threshold
    @insurance_pool_threshold ||= SystemParameter.current(:insurance_pool_threshold, default: DEFAULT_INSURANCE_POOL_THRESHOLD).to_i
  end

  # [S6.17] Computed threshold in wei for on-chain balance comparison.
  def insurance_pool_threshold_wei
    insurance_pool_threshold * WEI_MULTIPLIER
  end
end
