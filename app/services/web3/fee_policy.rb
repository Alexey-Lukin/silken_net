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
  # 🔑 ДВІ ПОЛІТИКИ, І ПОРЯДОК МІЖ НИМИ — ПРИСУД (ARCH.62, 2026-09-05):
  # ENV-число, якщо задане, б'є вимір — оператор, що пінить cap, робить це
  # свідомо і його рішення сильніше за миттєвий стан мережі. Мережа без ENV
  # ПИТАЄТЬСЯ, а не лишається на gem-дефолті. Ethereum несе ратифіковані L1-числа
  # дефолтами `ENV.fetch`, тож поведінка якоря НЕ змінюється; Polygon і Celo
  # ENV не мають ніде — саме вони й переходять на вимір.
  #
  # 📐 ЧОМУ ВЗАГАЛІ ВИМІР, А НЕ ЧИСЛО — це не «краще», а ЄДИНЕ чесне, і показав
  # це один прогін проти живих нод 2026-09-05:
  #   · Polygon Amoy: tip ≈ 99.57 Gwei, base = 63 wei (≈0) — ЧАЙОВА домінує;
  #   · Celo mainnet: base = 200 Gwei, tip = 2.5 Gwei — БАЗА домінує.
  # Форми ІНВЕРСНІ, тож жодна одностороння евристика («бери tip» ⊥ «бери base×N»)
  # не покриває обидві мережі, а спільного числа не існує в принципі. І та сама
  # проба винесла вирок статус-кво: gem-cap 42.69 Gwei нижчий за потрібне на
  # ОБОХ (`includable = false`), тобто дефект був не гіпотезою, а станом.
  #
  # 🔒 СТЕЛІ, названі явно:
  #   · динамічне читання ЗАСТАРІВАЄ разом із клієнтом. Клієнт кешується
  #     per-thread (`RpcConnectionPool`), а Sidekiq-потоки живуть довго — тож
  #     fee виміряний НА НАРОДЖЕННІ і не оновлюється сам. Це свідомо: вимір на
  #     кожному `transact` повернув би політику в `LocalEnvSigner` (див. вище,
  #     78 падінь) і бив би по RPC на кожну монету. Шлях апгрейду названий —
  #     TTL на кеш пулу або `reset!` при детекті застряглого tx (→ `00_07` ARCH.62);
  #   · `eth_fee_history` НЕПРИДАТНИЙ через цей гем — виміряно, не припущено:
  #     гем маршалить аргументи в hex-quantity рядки, а нода чекає на
  #     `float64` у percentiles → `invalid argument 2: json: cannot unmarshal
  #     string into Go value of type float64` (падає і на `[50]`, і на `[50.0]`).
  #     Тому cap рахується з `baseFeePerGas` останнього блоку, а не з історії;
  #   · коли й вимір, і ENV відсутні, політика НЕ вигадує число — вона голосно
  #     мовчить і лишає gem-дефолт. Дефект лишається ОГОЛОШЕНИМ;
  #   · мережа впізнається за ІМЕНЕМ ENV-ключа, тож ключ, названий без імені
  #     мережі, політики не дістане — це судить `spec/services/web3/fee_policy_spec.rb`.
  # =========================================================================
  module FeePolicy
    GWEI = 10**9

    # Запас над `baseFeePerGas` на час, поки tx чекає включення. За EIP-1559 база
    # росте максимум на 12.5% за блок, тож 2× переживає ≈6 блоків — галузевий
    # дефолт (ethers.js рахує cap так само: `base * 2 + tip`). Множник свідомо
    # НЕ ENV-ручка: він про механіку EIP-1559, однакову на всіх ланцюгах, а не
    # про мережу — ручкою тут є сам вибір «вимір ⊥ пін», а не його коефіцієнт.
    BASE_FEE_HEADROOM = 2

    # 🔴 ВИМІР РОБИТЬСЯ ЛИШЕ НАД СПРАВЖНІМ КЛІЄНТОМ, і цю межу продиктував ВИМІР,
    # а не смак: перша редакція питала ціни в будь-якого переданого обʼєкта й
    # повалила **175 прикладів** сюїти одним рядком — рівно той клас, що вже
    # коштував 78 падінь, коли політика жила в `LocalEnvSigner` і вимагала
    # `chain_id` (див. шапку). Урок той самий і він УДРУГЕ: масові падіння —
    # не привід «дописати стаби», а сигнал, що дім не той.
    #
    # 🔑 Підстава НЕ «щоб тести не падали», і різницю треба тримати: `apply!` —
    # ПУБЛІЧНИЙ метод, що приймає довільний обʼєкт. **Присвоїти** два атрибути
    # безпечно будь-кому, хто їх приймає; **допитувати** довільний обʼєкт
    # JSON-RPC-командами — ні. Тож контракт такий: вимір — для того, з ким ми
    # справді вміємо говорити ланцюгом; статика — для всіх. У проді пул родить
    # рівно ці два класи, тож жодного клієнта вимір не втрачає.
    # ⊕ Побічний і свідомий наслідок: верифікуючий дубль (`instance_double`) під
    # `is_a?` не підпадає, тож спека, якій fee байдужий, стабів не потребує.
    # Спека, якій вимір ВАЖЛИВИЙ, бере справжній `Eth::Client.create(url)`
    # (конструктор мережі не чіпає) і мокає на ньому лише два read-методи —
    # так приклад судить ту саму гілку, що й прод.
    MEASURABLE_CLIENTS = [ Eth::Client, Web3::ResilientClient ].freeze

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
        if max_gwei
          client.max_fee_per_gas = max_gwei * GWEI
          client.max_priority_fee_per_gas = priority_gwei * GWEI
          return
        end

        return if apply_measured!(client, network)

        warn_unset(network)
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

      # Питає мережу і ставить fee з живих чисел. `true` = поставлено.
      #
      # 🔬 ФОРМИ ВІДПОВІДЕЙ ТУТ ВИМІРЯНІ, А НЕ ВГАДАНІ — і це була сама умова,
      # під якою ARCH.62 тримав цю ногу закритою («формат на money-path не можна
      # вгадувати»). Прогін проти `polygon-amoy-bor-rpc.publicnode.com` і
      # `forno.celo.org` 2026-09-05 показав: гем відповідь НЕ розгортає, віддає
      # сирий JSON-RPC конверт, а число всередині — hex-QUANTITY рядок:
      #   `eth_max_priority_fee_per_gas` → {"jsonrpc"=>"2.0","id"=>2,"result"=>"0xdf8475800"}
      #   `eth_get_block_by_number`      → {"result"=>{"baseFeePerGas"=>"0x3f", …}}
      # Саме тому обидва читання йдуть через `hex_quantity` і жодне не довіряє
      # типу: `to_i(16)` на `nil` мовчки дав би 0, а нуль тут — не «дешево», а
      # НЕВИМІРЯНО (той самий клас, що розводять три balance-гарди money-path).
      #
      # ⚠️ Помилку ЇМО свідомо (`rescue StandardError` → `false`): вимір робиться
      # на НАРОДЖЕННІ клієнта, тож виняток тут завалив би не транзакцію, а
      # створення клієнта — тобто увесь money-path через мертву ноду. Падіння
      # веде на статику, статика — на гучне мовчання.
      #
      # ⛔ І ОДРАЗУ МЕЖА, бо перша редакція цього коментаря стверджувала протилежне
      # і була СПРОСТОВАНА власною спекою: `rescue StandardError` НЕ рятує тестові
      # дублі. `RSpec::Mocks::MockExpectationError` успадковується від `Exception`,
      # не від `StandardError`, тож `instance_double` без цих двох стабів падає
      # НАСКРІЗЬ. Тобто «моки провалюються сходинкою нижче» — хибне; хто створює
      # клієнт мокою, мусить оголосити й вимір. Ширшати до `rescue Exception` тут
      # ЗАБОРОНЕНО: на грошовому шляху це ковтало б і `Interrupt`, і `NoMemoryError`.
      def apply_measured!(client, network)
        return false unless MEASURABLE_CLIENTS.any? { |k| client.is_a?(k) }

        tip = hex_quantity(client.eth_max_priority_fee_per_gas, "result")
        base = hex_quantity(client.eth_get_block_by_number("latest", false).to_h["result"], "baseFeePerGas")
        return false if tip.nil? || base.nil?

        client.max_priority_fee_per_gas = tip
        client.max_fee_per_gas = (base * BASE_FEE_HEADROOM) + tip
        Rails.logger.info(
          "⛽ [ARCH.62] #{network}: fee виміряно — tip #{(tip.to_f / GWEI).round(2)} Gwei, " \
          "base #{(base.to_f / GWEI).round(4)} Gwei, cap #{((base * BASE_FEE_HEADROOM + tip).to_f / GWEI).round(2)} Gwei"
        )
        true
      rescue StandardError => e
        Rails.logger.warn("⚠️ [ARCH.62] #{network}: вимір fee не вдався (#{e.class}: #{e.message}) — падаю на статику")
        false
      end

      # hex-QUANTITY рядок з JSON-RPC конверта → wei. `nil`, якщо поля немає або
      # воно не hex: відсутній вимір мусить лишитись ВІДСУТНІМ, а не стати нулем.
      def hex_quantity(envelope, key)
        raw = envelope.is_a?(Hash) ? envelope[key] : nil
        return nil unless raw.is_a?(String) && raw.match?(/\A0x[0-9a-f]+\z/i)

        raw.to_i(16)
      end

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
