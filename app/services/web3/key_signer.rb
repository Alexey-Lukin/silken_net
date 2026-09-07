# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Web3
  # =========================================================================
  # 🔏 KEY SIGNER (SEC.17 — the surface every money service talks to)
  # =========================================================================
  # `#address` · `#transact(client, …)` · `#static_call(client, …)` over ONE key
  # object that quacks like `Eth::Key`. Measured against eth 0.5.17 (06_04 §5.5):
  # `Eth::Client#transact` → `send_transaction` → `Eth::Tx::Eip1559#sign(key)`
  # touch exactly `key.address` and `key.sign(blob, chain_id)` — no `is_a?`
  # anywhere on that path — so a backend is just a different key object:
  #   `LocalEnvSigner` — `Eth::Key` derived from deploy-ENV plaintext (default);
  #   `KmsSigner`      — `KmsKey`, private key resident in a Cloud KMS HSM.
  # The split lives HERE and in `OracleSigner.for`; no call-site knows which.
  #
  # 🔴 Клієнт — ПАРАМЕТР кожного виклику, ніколи не стан підписанта:
  # `Web3::RpcConnectionPool.client_for` = per-thread кеш, тож підписант, що
  # тримав би клієнта, дублював би той кеш (і пережив би `reset!`).
  # =========================================================================
  class KeySigner
    # =====================================================================
    # ⛽💰 RESERVE-GATE — «чи проїде ЦЯ транзакція», а не «чи є ЩОСЬ на рахунку»
    # =====================================================================
    # 🔴 **Куплено живим інцидентом на canopy 2026-09-06:**
    # `MintBatchCollectorWorker` упав `insufficient funds for gas * price + value`
    # при балансі **рівно `0.05` MATIC — рівно `oracle_min_balance_matic`**. Тобто
    # операторський поріг був ЗЕЛЕНИЙ (`ratio = 1.00`), а money-шлях непрацездатний,
    # і зонд балансів прочитався як OK, бо порівнював баланс із ВИГАДАНОЮ підлогою.
    #
    # 🔑 **Геометрія ARCH.95: гард міряв не ту величину, що предмет.** «Скільки Є»
    # і «скільки ТРЕБА на одну операцію» — різні питання, і константа не відповідає
    # на друге НІ ЗА ЯКИХ обставин (виміряно 2026-09-06, дві незалежні осі): на Amoy
    # `baseFee ≈ 0`, тож усю ціну задає ЧАЙОВА — `55.25` Gwei проти `99.57` Gwei
    # добою раніше, тобто майже вдвічі; а `gasLimit` тут не константа за побудовою
    # (`#gas_limit_for` = `eth_estimate_gas × HEADROOM`, і для `batchMint` він росте
    # з розміром батчу). Отже число або замале в пік, або завелике в затишшя.
    #
    # ⚖️ **Присуд founder-а 2026-09-07: предикат стоїть ПОРУЧ, а не ЗАМІСТЬ порога.**
    # `oracle_min_balance_*` лишається ОПЕРАТОРСЬКОЮ шкалою (він годує `ratio`,
    # дашборд і два алерт-правила — `Treasury::MonitorService`); тут судиться рівно
    # ціна цієї операції. Дві шкали лишаються розведеними навмисно: злиття їх
    # змусило б алерт стрибати разом із чайовою мережі.
    #
    # 📐 **Формула — та сама, що перевіряє сам EVM:** `gasLimit × maxFeePerGas + value`.
    # ⛔ Не `gasUsed`: ланцюг РЕЗЕРВУЄ за лімітом, а не за фактом, і відхиляє
    # транзакцію саме на резерві (решта повертається). Тому предикат не «оцінює
    # витрату» — він відтворює вирок ноди ДО того, як ми за нього заплатили.
    #
    # 🔴 **ЧОМУ ТУТ, І ЦЕ НЕ ВИБІР ЗРУЧНОСТІ: `gas_limit` існує ЛИШЕ всередині цього
    # методу.** Він народжується `eth_estimate_gas`-ом на КОЖЕН виклик (рядок нижче),
    # тож будь-який гард у сервісі — там, де живе поріг, — фізично не має другого
    # множника й на питання «чи проїде ЦЯ транзакція» відповісти не може.
    # ⊕ Наслідок для периметра: гейт покриває УСІ EVM-ланцюги одним домом (Polygon ·
    # Celo · Ethereum-якір ідуть через цей шов). ⛔ **Solana ПОЗА ним за побудовою** —
    # `Solana::MintingService` не є `Eth::Client` і лампорти тут не рахуються; вдавати
    # покриття було б гірше за відмову.
    #
    # 🔑 **Текст винятку НЕСЕ англійський маркер `insufficient funds`, і це КОНТРАКТ,
    # не стиль.** Три незалежні доми класифікують саме цей рядок, і всі троє мусять
    # прочитати наш вирок так само, як прочитали б вирок ноди:
    #   · `BlockchainMintingService#transact_error_pre_broadcast?` → `fail!`+retry,
    #     а НЕ `manual_review` (інакше ми самі створювали б лімб, з якого виходу нема);
    #   · `Celo::CommunityRewardService::REJECTED_PATTERNS`;
    #   · `Web3::TransactionErrorClassifier` → код `:insufficient_funds` (той їде в
    #     незворотний IPFS-пін, тож клас мусить бути названий, а не `:unknown`).
    # ⚠️ Звʼязок доведено ПІНОМ (`key_signer_transact_spec`), не цим абзацом —
    # докстрінг, що називає споживачів, гниє тихіше за код.
    # ⛔ Не вживати в тексті токен `reserve-gate` латиницею: у класифікаторі є вужче
    # правило `:reserve_hold` (`/reserve-?gate/i`), і хоча порядок RULES ставить
    # `:insufficient_funds` вище, покладатись на ПОРЯДОК замість однозначності —
    # рівно та крихкість, яку цей коментар і знімає.
    class InsufficientGasReserve < StandardError; end

    # @param key [#address, #sign] `Eth::Key` or a duck-typed twin (`Web3::KmsKey`)
    def initialize(key)
      @key = key
    end

    # 🔴 Повертає адресу ключа ВЕРБАТИМ (обʼєкт `Eth::Address`, не рядок).
    # Значення інтерполюється у Kredis-ключ `lock:web3:oracle:#{address}` — це
    # точка серіалізації nonce'ів ARCH.47 на money-path. Будь-яка нормалізація
    # (`.to_s`, `.downcase`, checksum-фліп) ПЕРЕСУВАЄ цей ключ, тобто два
    # процеси взяли б різні локи на одну адресу → колізія nonce.
    def address
      @key.address
    end

    # ⊕ [ARCH.62] Fee тут НЕ ставиться свідомо: політика живе на місці народження
    # клієнта (`Web3::RpcConnectionPool`), бо там мережа відома СТАТИЧНО з імені
    # ENV-ключа. Спроба тримати її тут вимагала б `client.chain_id` від кожного
    # тестового дубля (78 падінь у 22 файлах) — тобто дім був би не той.
    # @param client [Eth::Client] per-thread клієнт мережі (параметр, не стан)
    def transact(client, contract, function, *args, **kwargs)
      # ⛔ kwargs чіпаються ЛИШЕ коли є що сказати: без оцінки вони проходять
      # НЕДОТОРКАНИМИ, і гем застосовує власний фолбек рівно як раніше. Це не
      # стиль — два піни (`kms_signer_spec` · `local_env_signer_spec`) стережуть
      # саме pass-through, і зайвий `gas_limit: nil` зробив би їх хибними,
      # стверджуючи зміну контракту там, де її немає.
      unless kwargs.key?(:gas_limit)
        estimated = gas_limit_for(client, contract, function, args, kwargs)
        kwargs = kwargs.merge(gas_limit: estimated) if estimated
      end
      assert_gas_reserve!(client, kwargs[:gas_limit], kwargs[:value])
      client.transact(contract, function, *args, sender_key: @key, **kwargs)
    end

    # =====================================================================
    # ⛽ GAS LIMIT — СЕСТРА ARCH.62, І ВОНА ЖИЛА НЕПОМІЧЕНОЮ ПОРУЧ
    # =====================================================================
    # 🔴 Виміряно на живому canopy 2026-09-05: **44 мінти SCC поспіль осіли в
    # `manual_review` з `tx_hash = nil`**, тобто жодна не пішла в мережу, а
    # ланцюг відповідав дослівно `Transaction gas limit is too low, try 74494!`.
    # Причина — гем: `Eth::Client#transact` без `gas_limit:` бере
    # `Tx.estimate_intrinsic_gas(contract.bin)`, тобто **ІНТРИНСИК** (21 000 +
    # байти calldata) — газ на ДОСТАВКУ транзакції, не на ВИКОНАННЯ функції.
    # Для `mint()`, що пише в сторедж, виконання й дає всю різницю.
    #
    # 🔑 **Геометрія тотожна ARCH.62, і саме тому дефект вижив:** шапка
    # `Web3::FeePolicy` каже «присвоєння в усьому `app/` існувало РІВНО ОДНЕ —
    # `Ethereum::StateAnchorService`». Це речення було правдиве й про
    # `gas_limit` (L1 несе `ETHEREUM_GAS_LIMIT`), а ми лікували вісь ЦІНИ й не
    # подивились на вісь ЛІМІТУ в тому самому виклику.
    #
    # ⛔ **Константою це НЕ лікується, і це не смак:** `batchMint` витрачає газ
    # пропорційно розміру батчу, тож одне число було б або замалим для великого
    # батчу, або брехнею про малий. Асиметрія при цьому зворотна до fee:
    # зависокий ЛІМІТ не коштує нічого (платиться газ ВИКОРИСТАНИЙ; ліміт лише
    # мусить бути покритий балансом), а занизький відхиляє транзакцію ДО
    # відправки. Тому: питаємо мережу й додаємо запас.
    #
    # ⚠️ `HEADROOM` не декоративний — оцінка робиться на ПОТОЧНОМУ стані, а між
    # нею й включенням стан міняється (холодний слот стореджу стає теплим,
    # чужий мінт лягає першим). Занижена на кілька відсотків оцінка дала б
    # рівно ту саму відмову, яку цей код і знімає.
    #
    # 🔴 **`MEASURABLE_CLIENTS` — не церемонія, а урок ЦЬОГО Ж дня:** перша
    # редакція виміру fee допитувала будь-який переданий обʼєкт і повалила 175
    # прикладів сюїти. Тестовий дубль не є `Eth::Client`, тож допитувати його
    # не можна — і `rescue StandardError` тут не рятує, бо
    # `RSpec::Mocks::MockExpectationError` є `Exception`. Дубль просто лишається
    # на гем-дефолті, як і раніше.
    HEADROOM = 1.25

    private

    def gas_limit_for(client, contract, function, args, kwargs)
      return nil unless Web3::FeePolicy::MEASURABLE_CLIENTS.any? { |k| client.is_a?(k) }

      data = contract.function(function, args: args.size).encode_call(*args)
      envelope = client.eth_estimate_gas(
        { from: address.to_s, to: kwargs[:address] || contract.address, data: data }
      )
      raw = envelope.is_a?(Hash) ? envelope["result"] : nil
      return nil unless raw.is_a?(String) && raw.match?(/\A0x[0-9a-f]+\z/i)

      (raw.to_i(16) * HEADROOM).ceil
    rescue StandardError => e
      Rails.logger.warn("⚠️ [gas] оцінка ліміту не вдалась (#{e.class}: #{e.message}) — лишаю гем-дефолт")
      nil
    end

    # Повний контракт — у шапці `InsufficientGasReserve` вище.
    #
    # ⚠️ **Стеля оголошена: гейт fail-OPEN на збої ПРИЛАДУ, і це присуд, а не недогляд.**
    # Він судить лише те, що зміг ПРОЧИТАТИ: без оцінки ліміту, без ціни або без
    # балансу вирок не виноситься, і транзакція йде як раніше — бо блокувати money-path
    # через RPC-гикавку означає купити недоступність дорожче за дефект, який гейт
    # стереже (та сама підстава, з якої `Web3NetworkGuard` свідомо НЕ робить живої
    # `eth_chainId`-проби на буті). Ціна відмови названа: мовчазний гейт помиляється
    # в бік ПРОПУСКУ, тож `warn` тут не косметика — це єдиний слід його сліпоти.
    def assert_gas_reserve!(client, gas_limit, value)
      return unless Web3::FeePolicy::MEASURABLE_CLIENTS.any? { |k| client.is_a?(k) }
      return if gas_limit.nil?

      max_fee = client.max_fee_per_gas
      return unless max_fee.is_a?(Numeric) && max_fee.positive?

      reserve = (gas_limit.to_i * max_fee).to_i + value.to_i
      balance = client.get_balance(address)
      return unless balance.is_a?(Numeric)
      return if balance >= reserve

      raise InsufficientGasReserve,
            "🚨 [Web3] insufficient funds для ЦІЄЇ транзакції (резерв газу перевірено ДО відправки): " \
            "баланс #{balance} wei < резерв #{reserve} wei " \
            "(gasLimit #{gas_limit.to_i} × maxFeePerGas #{max_fee.to_i}#{" + value #{value.to_i}" if value.to_i.positive?}). " \
            "⛔ Це НЕ поріг `oracle_min_balance_*` — той міряє операторську шкалу; " \
            "тут виміряна ціна саме цієї операції, і вона рухома (чайова мережі × розмір батчу)."
    rescue InsufficientGasReserve
      raise
    rescue StandardError => e
      Rails.logger.warn("⚠️ [gas] резерв не перевірено (#{e.class}: #{e.message}) — вирок НЕ виноситься, транзакція йде")
    end

    public

    # `eth_call`-симуляція (zero-gas). Ім'я `static_call`, бо `call` на Ruby-обʼєкті
    # читалось би як proc-виклик.
    #
    # 🔴 [SEC.17] ВІДПРАВНИК ЇДЕ ЯК `from:`, І ЦЕ НЕ СТИЛЬ. `Eth::Client#call` читає
    # рівно `kwargs[:address] · [:from] · [:gas] · [:gas_price] · [:value]` і
    # `sender_key:` не читає ЖОДНОГО разу — при тому, що власний докстрінг гема
    # його рекламує (eth 0.5.17 `client.rb`: докстрінг ~271, тіло 275-296).
    # Тобто попередня форма давала `from: nil`, `.compact` його викидав, і
    # симуляція йшла БЕЗ відправника. Ціна не теоретична: `batchMint` має
    # `onlyRole(MINTER_ROLE)`, тож на живому ланцюгу dry-run ревертив би на
    # КОЖНОМУ батчі → `batch_dry_run_reverts?` → бінарний пошук отруєного запису
    # щоразу, на чистих даних.
    # ⚠️ `**kwargs` стоїть ПІСЛЯ — викликач, що передав власний `from:`, виграє.
    # ⛔ Не повертати `sender_key:` «про всяк випадок»: kwarg, якого приймач не
    # читає, є оголошенням без механізму — саме він тут і коштував дефекту.
    # @param client [Eth::Client] per-thread клієнт мережі (параметр, не стан)
    def static_call(client, contract, function, *args, **kwargs)
      client.call(contract, function, *args, from: @key.address.to_s, **kwargs)
    end
  end
end
