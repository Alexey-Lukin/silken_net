# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "eth"
require "bigdecimal"

module KlimaDao
  # =========================================================================
  # 🌿 KLIMA DAO RETIREMENT SERVICE (ESG Carbon Credit Retirement)
  # =========================================================================
  # Інтегрує інфраструктуру KlimaDAO на Polygon для офіційного погашення
  # (retirement) вуглецевих кредитів SCC. Коли організація хоче довести свою
  # еко-нейтральність для ESG-звітності, вона спалює токени через KlimaDAO
  # і отримує криптографічний доказ погашення.
  #
  # Потік:
  #   1. Перевірка ЗАПАСУ МОНЕТ і типу токена (Guard Clause)
  #   2. Approve KlimaDAO контракту на витрату SCC
  #   3. Виклик retire(uint256) на KlimaDAO Retirement контракті
  #   4. Облік у БД: `esg_retired_balance ↑` — і НІЧОГО більше [ARCH.95 вісь 3]
  #   5. Запис BlockchainTransaction (`direction: :burn`) з аудитом
  # =========================================================================
  class RetirementService
    # ABI для ERC-20 approve та KlimaDAO retire
    APPROVE_ABI = '[{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}]'
    RETIRE_ABI  = '[{"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"retire","outputs":[],"stateMutability":"nonpayable","type":"function"}]'

    TOKEN_DECIMALS = 18

    class InsufficientBalanceError < StandardError; end
    class InvalidTokenTypeError < StandardError; end

    # ✅ [ARCH.95] ПРИСУД УХВАЛЕНО 2026-08-25 (машина за делегуванням founder).
    # Осей виявилось ЧОТИРИ, і четверта жила рівно там, де пункт вважав уже
    # виправленим. Усі закриті цим комітом; fail-closed гард знято.
    #
    #   1. ОДИНИЦЯ = МОНЕТИ (SCC). Дискримінатор ЗОВНІШНІЙ, не смаковий: клієнт
    #      погашає, щоб довести tCO₂, а єдиний міст до tCO₂ — курс `2000 SCC =
    #      1 tCO₂` (`00_04 §Фінансові Константи`); бали в ту формулу не входять
    #      узагалі. Підпирає з трьох боків: `retire(uint256)` — чужий ABI KlimaDAO,
    #      приймає токени · `00_04` двічі каже «SCC» (тракт-таблиця + опис колонки)
    #      · «бали» зробили б розмір НЕОБОРОТНОГО спалення функцією поточного
    #      DAO-голосу, бо поріг емісії DAO-керований.
    #
    #   2. НАПРЯМОК = явна колонка `blockchain_transactions.direction`
    #      ([ARCH.95] у моделі). Деривація з `sourceable_type` була ратифікована
    #      [ARCH.101] на ПЕРЕДУМОВІ «єдиний slash-шлях», яку це погашення знімає.
    #
    #   3. GROSS. `balance`/`locked_balance`/`available_balance` НЕ РУХАЮТЬСЯ.
    #      `esg_retired_balance` став лічильником погашених МОНЕТ. Записана в пункті
    #      альтернатива (`available_balance = balance − locked − esg_retired`) сама
    #      несла дефект одиниці: щоб мати SCC, гаманець їх намінтив, а мінт уже
    #      наклав ті бали в `locked_balance` НАЗАВЖДИ (reserve-семантика `04_01 §6`)
    #      — віднімати їх удруге є подвійним списанням. Виняток із gross-визначення
    #      зникає сам, без нової формули.
    #
    #   4. 🔴 ГАРД МІРЯВ НЕ ТУ ВЕЛИЧИНУ — вісь, якої пункт не називав, бо вважав
    #      її закритою [ARCH.56]. `available_balance = balance − locked_balance` є
    #      «скільки балів ще МОЖНА сконвертувати», а не «скільки монет Є». Дві
    #      протилежні поломки: гаманець, що намінтив усе (`available = 0`), дістав
    #      би ВІДМОВУ погасити наявні SCC; гаманець, що не мінтив нічого, дістав би
    #      ДОЗВІЛ спалити те, чого не має. ARCH.56 рухав цей гард `balance` →
    #      `available_balance`, тобто ВСЕРЕДИНІ балової шкали, не спитавши одиниці.
    #      Тепер запас читається там, де він справді живе — `net_minted_supply`,
    #      яка після осі (2) уже віднімає власні погашення.

    # [ARCH.95] Одиниця НЕРЕПРЕЗЕНТОВНА в хибному вигляді: kwarg `scc:` замість
    # голого скаляра. Позиційний виклик тепер неможливий, тож наступний викликач
    # не має способу мовчки передати бали — на відміну від форми, що цей клас
    # і породила.
    def initialize(wallet, scc:)
      @wallet = wallet
      @scc_to_retire = BigDecimal(scc.to_s)
    end

    def retire_carbon!
      validate!

      # 1. WEB3: Виконуємо блокчейн-операції ЗА МЕЖАМИ DB-транзакції,
      #    щоб не тримати довгі локи під час RPC-запитів.
      tx_hash = execute_blockchain_retirement

      # 2. DB: Атомарний облік погашення + аудит-запис
      ActiveRecord::Base.transaction do
        @wallet.lock!

        # Повторна перевірка після блокування (Race Condition Protection).
        if retirable_scc < @scc_to_retire
          raise InsufficientBalanceError,
                "Запас змінився під час транзакції (Доступно: #{retirable_scc} SCC, Потрібно: #{@scc_to_retire} SCC)"
        end

        # [ARCH.95 вісь 3] Балансові колонки НЕ рухаються: `balance` лишається
        # gross-лічильником балів за все життя дерева (`04_01 §6`), і перше поле
        # тижневого L1-якоря (`Wallet.sum(:balance)`) більше не переписується
        # заднім числом. Рухається рівно лічильник погашених МОНЕТ.
        @wallet.increment!(:esg_retired_balance, @scc_to_retire)

        create_retirement_transaction(tx_hash)
      end

      Rails.logger.info "🌿 [KlimaDAO] Погашено #{@scc_to_retire} SCC для Wallet ##{@wallet.id}. TX: #{tx_hash}"
    end

    private

    def validate!
      # Guard Clause: Перевірка типу токена
      unless @wallet.blockchain_transactions.exists?(token_type: :carbon_coin)
        raise InvalidTokenTypeError,
              "Wallet ##{@wallet.id} не має carbon_coin транзакцій. Погашення доступне лише для SCC."
      end

      # Guard Clause: достатність ЗАПАСУ МОНЕТ [ARCH.95 вісь 4].
      if retirable_scc < @scc_to_retire
        raise InsufficientBalanceError,
              "Недостатньо SCC (Доступно: #{retirable_scc}, Потрібно: #{@scc_to_retire})"
      end
    end

    # 🔴 [ARCH.95 вісь 4] Скільки МОНЕТ цей гаманець реально має на руках.
    #
    # ⛔ Це НЕ `available_balance`. Той є `balance − locked_balance`, тобто «скільки
    # БАЛІВ ще можна сконвертувати в монети» — величина протилежного боку конвертації.
    # Монети з'являються рівно від мінту, тож запас = чиста емісія цього гаманця.
    #
    # ⚠️ Віднімати `esg_retired_balance` тут НЕ ТРЕБА й НЕ МОЖНА: після [ARCH.95] кожне
    # погашення пише власний рядок із `direction: :burn`, тож `net_minted_supply` уже
    # його відняла. Друге віднімання дало б −2× за кожне погашення.
    def retirable_scc
      @wallet.blockchain_transactions.net_minted_supply(:carbon_coin)
    end

    def execute_blockchain_retirement
      client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
      # [INF.22] Dedicated Klima-підписант (легасі спільний ORACLE_PRIVATE_KEY retired) —
      # E.2-ізоляція blast-radius. Ключ інжектиться при активації Klima-шляху (06_04 §2.1).
      oracle_key = Eth::Key.new(priv: ENV.fetch("ORACLE_KLIMA_PRIVATE_KEY"))

      scc_contract_address = ENV.fetch("CARBON_COIN_CONTRACT_ADDRESS")
      klima_contract_address = ENV.fetch("KLIMA_RETIREMENT_CONTRACT")

      scc_contract = Eth::Contract.from_abi(
        name: "SilkenCarbonCoin",
        address: scc_contract_address,
        abi: APPROVE_ABI
      )

      klima_contract = Eth::Contract.from_abi(
        name: "KlimaRetirement",
        address: klima_contract_address,
        abi: RETIRE_ABI
      )

      # [ARCH.95] `@scc_to_retire` — МОНЕТИ, тож `× 10**18` тут коректний за
      # визначенням: це ERC-20 decimals того самого SCC, який приймає `retire(uint256)`.
      amount_in_wei = (@scc_to_retire * 10**TOKEN_DECIMALS).to_i

      # Step 1: Approve KlimaDAO контракту на витрату SCC
      client.transact(
        scc_contract, "approve", klima_contract_address, amount_in_wei,
        sender_key: oracle_key, legacy: false
      )

      # Step 2: Виклик retire на KlimaDAO контракті
      tx_hash = client.transact(
        klima_contract, "retire", amount_in_wei,
        sender_key: oracle_key, legacy: false
      )

      tx_hash
    end

    def create_retirement_transaction(tx_hash)
      @wallet.blockchain_transactions.create!(
        amount: @scc_to_retire,
        token_type: :carbon_coin,
        # [ARCH.95 вісь 2] ДРУГИЙ рід вилучення з обігу поруч зі слешем. Без цього
        # рядка `net_minted_supply` рахувала б погашення ЕМІСІЄЮ — а вона годує
        # `total_scc_supply` тижневого L1-якоря (`05_04 §3`) і базу розміру спалення
        # (`05_05 §3`), тобто погашення завищувало б майбутній слешинг.
        # ⛔ `sourceable` тут НЕМА свідомо: погашення не є слешем, і саме ця
        # відсутність робила стару деривацію хибною.
        direction: :burn,
        status: :sent,
        tx_hash: tx_hash,
        notes: "🌿 ESG Retirement via KlimaDAO: #{@scc_to_retire} SCC погашено для вуглецевої нейтральності.",
        to_address: ENV.fetch("KLIMA_RETIREMENT_CONTRACT")
      )
    end
  end
end
