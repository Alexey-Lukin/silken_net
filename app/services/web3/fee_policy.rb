# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Web3
  # =========================================================================
  # ⛽ FEE POLICY (ARCH.62 — EIP-1559 fee на КОЖНОМУ EVM-клієнті)
  # =========================================================================
  # 🔴 ПРОБЛЕМА НЕ В ТОМУ, ЩО СТЕЛІ БРАКУВАЛО — вона вже СТОЯЛА, і обрав її
  # хтось третій. `eth 0.5.17` присвоює fee у КОНСТРУКТОРІ клієнта
  # (`client.rb`: `@max_fee_per_gas = Tx::DEFAULT_GAS_PRICE` = 42.69 Gwei,
  # `@max_priority_fee_per_gas = Tx::DEFAULT_PRIORITY_FEE` = 1.01 Gwei), а
  # `#send_transaction` при `legacy: false` вливає рівно ці атрибути як
  # `max_gas_fee`/`priority_fee` і актуальної ціни з ноди не питає НІКОЛИ.
  # Власний коментар гема над обома константами — `# Do not use.`
  #
  # До цього класу присвоєння в усьому `app/` існувало РІВНО ОДНЕ —
  # `Ethereum::StateAnchorService` (L1). Кожен Polygon/Celo-transact грошового
  # шляху (`mint` · `batchMint` · `slashUpTo` · Klima `approve`/`retire` ·
  # Etherisc · Puro · Celo-reward) їхав на gem-дефолтах.
  #
  # ⚠️ НАПРЯМОК РИЗИКУ ІНВЕРСНИЙ ДО ІНТУЇЦІЇ: 42.69 Gwei — не стеля ВИТРАТ, а
  # підлога ГОТОВНОСТІ МАЙНИТИСЬ. За EIP-1559 платиться `baseFee + priorityFee`,
  # а `maxFee` лише обмежує; тож занизький `maxFee` не економить — він робить
  # tx невключабельним. Режим відмови детермінований: tx не майниться → вічний
  # `:sent` → `StuckSentTransactionSweeperWorker` лише re-poll'ить (re-broadcast
  # і gas-bump у дереві НЕМАЄ ніде, і це записана заборона) → `MintingRollbackService`
  # → `manual_review`, тобто заблоковані кошти й ручний розбір.
  #
  # 🏠 ДІМ — МІСЦЕ НАРОДЖЕННЯ КЛІЄНТА, і це вибір, а не зручність.
  # Перша редакція ставила політику в `LocalEnvSigner#transact` і питала мережу
  # через `client.chain_id`. Вона працювала — і повалила 78 прикладів у 22
  # файлах, бо кожен верифікуючий дубль `Eth::Client` мусив би тепер знати
  # `chain_id`. Це не «полагодити моки»: 78 падінь були СИГНАЛОМ, що дім
  # обрано не той. `Web3::RpcConnectionPool#build_client` знає `rpc_url_env_key`,
  # тож мережа деривується СТАТИЧНО з його імені — нуль RPC, нуль вимог до
  # тестових дублів, і кожен клієнт дерева народжується вже з політикою.
  #
  # 🔒 СТЕЛІ, названі явно:
  #   · політика НЕ питає ціни в мережі. Гем це УМІЄ (`eth_gas_price`,
  #     `eth_max_priority_fee_per_gas`, `eth_fee_history` існують справжніми
  #     методами — `Api::COMMANDS` породжує їх через `define_method`, тобто це
  #     не «лише імена в реєстрі»), і динамічний варіант зняв би потребу в
  #     числі взагалі. Він НЕ відвантажений свідомо: формат відповідей на
  #     money-path не можна вгадувати, а живої ноди для прогону немає
  #     (→ `00_07` ARCH.62);
  #   · для мережі БЕЗ заданого ENV політика не вигадує число — вона голосно
  #     мовчить і лишає gem-дефолт. Тобто дефект стає ОГОЛОШЕНИМ і отримує
  #     важіль, але ратифікація величини лишається присудом (⚖️);
  #   · мережа впізнається за ІМЕНЕМ ENV-ключа, тож ключ, названий без імені
  #     мережі, політики не дістане — це судить `spec/services/web3/fee_policy_spec.rb`.
  # =========================================================================
  module FeePolicy
    GWEI = 10**9

    class << self
      # Ставить fee-атрибути щойно створеного клієнта під його мережу.
      # No-op для мережі без політики — але з ОДНОРАЗОВИМ гучним логом.
      #
      # @param client [Eth::Client, Web3::ResilientClient] клієнт мережі
      # @param rpc_url_env_key [String] ENV-ключ, з якого клієнт народився
      def apply!(client, rpc_url_env_key)
        network = network_for(rpc_url_env_key)
        return if network.nil?

        max_gwei, priority_gwei = for_network(network)
        return warn_unset(network) if max_gwei.nil?

        client.max_fee_per_gas = max_gwei * GWEI
        client.max_priority_fee_per_gas = priority_gwei * GWEI
      end

      # Мережа з імені ENV-ключа (`ALCHEMY_POLYGON_RPC_URL` → :polygon).
      # Публічний, бо його судить спека-ліхтар: ключ money-шляху, з якого мережа
      # НЕ впізнається, лишився б на gem-дефолтах мовчки.
      def network_for(rpc_url_env_key)
        key = rpc_url_env_key.to_s.upcase
        return :polygon  if key.include?("POLYGON")
        return :celo     if key.include?("CELO")
        return :ethereum if key.include?("ETHEREUM")

        nil
      end

      private

      # ⛔ Імена ENV — ЛІТЕРАЛАМИ в `case`, по одному на мережу, дзеркально до
      # `Web3::OracleSigner`. Табличний lookup вивів би їх зі статично сканованої
      # множини, а разом із тим — з усякої можливості звірити деплой-поверхню очима.
      #
      # Ethereum несе успадковані числа (вони вже стояли на L1 і ратифіковані
      # там); Polygon і Celo дефолту в коді НЕ мають — див. стелю в шапці.
      def for_network(network)
        case network
        when :ethereum # L1 anchor
          [ ENV.fetch("ETHEREUM_MAX_FEE_GWEI", 100).to_i,
            ENV.fetch("ETHEREUM_PRIORITY_FEE_GWEI", 2).to_i ]
        when :polygon # увесь money-path (mint/burn/retire/claim)
          pair(ENV.fetch("POLYGON_MAX_FEE_GWEI", nil), ENV.fetch("POLYGON_PRIORITY_FEE_GWEI", nil))
        when :celo # community rewards
          pair(ENV.fetch("CELO_MAX_FEE_GWEI", nil), ENV.fetch("CELO_PRIORITY_FEE_GWEI", nil))
        end
      end

      # Обидва числа або жодного: половина політики гірша за її відсутність —
      # заданий cap без priority лишив би на дроті gem-дефолтний tip 1.01 Gwei,
      # тобто «полагоджено» на вигляд і невключабельно насправді.
      def pair(max, priority)
        return nil if max.blank? || priority.blank?

        [ max.to_i, priority.to_i ]
      end

      def warn_unset(network)
        @warned ||= Set.new
        return if @warned.include?(network)

        @warned << network
        Rails.logger.warn(
          "⚠️ [ARCH.62] #{network}: fee-політики НЕМА — на дроті лишаються gem-дефолти " \
          "42.69/1.01 Gwei, які нижчі за ринок Polygon і роблять tx невключабельним. " \
          "Важіль: #{network.to_s.upcase}_MAX_FEE_GWEI + #{network.to_s.upcase}_PRIORITY_FEE_GWEI (обидва)"
        )
      end
    end
  end
end
