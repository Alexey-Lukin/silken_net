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
