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
