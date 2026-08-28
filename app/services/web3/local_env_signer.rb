# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "eth"

module Web3
  # =========================================================================
  # 🗝️ LOCAL ENV SIGNER (SEC.17 default backend)
  # =========================================================================
  # Обгортка над локальним `Eth::Key`, дерівованим із deploy-ENV — тобто
  # рівно те, що money-сервіси робили інлайном. Жодної зміни поведінки:
  # `sender_key:` у `client.transact`/`client.call` лишається ТИМ САМИМ
  # `Eth::Key`-обʼєктом, решта kwargs проходить наскрізь недоторканою.
  #
  # 🔴 Клієнт — ПАРАМЕТР кожного виклику, ніколи не стан підписанта:
  # `Web3::RpcConnectionPool.client_for` = per-thread кеш, тож підписант, що
  # тримав би клієнта, дублював би той кеш (і пережив би `reset!`).
  # =========================================================================
  class LocalEnvSigner
    # @param private_key [String] hex-приватник із deploy-ENV
    def initialize(private_key)
      # ⛔ Не прибирати: `Eth::Key.new(priv: nil)` НЕ падає — він тихо генерує
      # ВИПАДКОВУ пару ключів. Тобто порожній/забутий ENV дав би валідного
      # підписанта з чужою адресою: mint пішов би з нуль-балансного гаманця, а
      # lock-key `lock:web3:oracle:<addr>` переїхав би на кожному рестарті.
      raise ArgumentError, "private_key порожній — Eth::Key згенерував би ВИПАДКОВУ пару" if private_key.blank?

      @key = Eth::Key.new(priv: private_key)
    end

    # 🔴 Повертає `Eth::Key#address` ВЕРБАТИМ (обʼєкт `Eth::Address`, не рядок).
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
      client.transact(contract, function, *args, sender_key: @key, **kwargs)
    end

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
