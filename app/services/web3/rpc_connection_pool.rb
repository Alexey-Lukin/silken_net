# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "eth"

module Web3
  # = ===================================================================
  # 🔗 RPC CONNECTION POOL (Thread-Safe Client Caching + Fallback Cascade)
  # = ===================================================================
  # Кешує Eth::Client інстанси per-thread для запобігання:
  # - Повторному встановленню TCP з'єднань при кожному виклику worker'а
  # - Rate-limiting від RPC провайдерів (Alchemy; keyless PublicNode/dRPC у фолбеках)
  # - Зайвому навантаженню на TLS handshake у Sidekiq-потоках
  #
  # Thread-safety: кожен Sidekiq thread отримує власний клієнт через Thread.current.
  # Це безпечно, оскільки Sidekiq worker'и виконуються ізольовано в межах потоку.
  #
  # [RPC FALLBACK CASCADE]: Підтримує масив резервних URL через fallback_env_keys.
  # При Net::ReadTimeout або HTTP 429 автоматично перемикається на наступний RPC.
  # Circuit Breaker вимикає провайдера після 3 послідовних збоїв на 60 секунд.
  #
  # Використання:
  #   # Простий виклик (зворотна сумісність):
  #   client = Web3::RpcConnectionPool.client_for("ALCHEMY_POLYGON_RPC_URL")
  #
  #   # З fallback cascade:
  #   client = Web3::RpcConnectionPool.client_for(
  #     "ALCHEMY_POLYGON_RPC_URL",
  #     fallback_env_keys: ["POLYGON_RPC_URL_FALLBACK_1"]
  #   )
  module RpcConnectionPool
    THREAD_KEY_PREFIX = :web3_rpc_client_

    # 🔴 [ARCH.114] ДІМ КАСКАДУ — МЕРЕЖА, а не сайт виклику. Заведено 2026-08-29
    # після емпіричної проби, і саме проба вирішила форму:
    #
    #   client_for("ALCHEMY_POLYGON_RPC_URL")                        # → Eth::Client, кешується
    #   client_for("ALCHEMY_POLYGON_RPC_URL", fallback_env_keys: […]) # → ТОЙ САМИЙ обʼєкт
    #
    # Кеш ключується ЛИШЕ на `rpc_url_env_key` (рядок нижче), тож каскад, оголошений
    # kwargʼом, мовчки не діяв, якщо в тому ж Sidekiq-потоці раніше побував сайт без
    # каскаду — а таких для Polygon вісім проти ОДНОГО з каскадом
    # (`MintingRollbackService`). Потоки живуть довго й перевикористовуються між
    # джобами, отже єдиний money-каскад Polygon працював лише тоді, коли його джоба
    # траплялась у потоці першою. Оголошення було, гарантії не було.
    #
    # 🔑 Чому реєстр, а не «дротувати kwarg на всіх 13 сайтах»: каскад є властивістю
    # МЕРЕЖІ (які ще ноди говорять тим самим ланцюгом), а не властивістю того, хто
    # цієї миті робить виклик. Реєстр робить кеш-ключ знову ЧЕСНИМ — для одного
    # env-ключа каскад тепер один, хай хто кличе, — і знімає цілий клас «сайт забув
    # kwarg», якого жоден гейт не бачить.
    # ⛔ Не додавай сюди ключа, якого немає в `.env.example`: порожній ENV просто
    # випадає зі списку (`build_client`), тож вигаданий ключ не зламає нічого й саме
    # тому проживе роками як фальшива обіцянка другого провайдера.
    # ⊕ Ethereum свідомо відсутній: L1-якір тижневий і низькочастотний, Sidekiq-retry його
    # покриває; keyless PublicNode для Ethereum виміряно живим з app-VM 2026-09-02, тож якщо
    # знадобиться — це рядок тут + `RPC_FALLBACK_URL_ENVS` гарда + `.env.example`, не акаунт.
    # ⛔ Другий слот НЕ заповнювати тим самим вендором, що й перший (Alchemy ×2): той
    # самий контролер двічі не додає незалежності, а лише рахує одного птаха двічі
    # (00_05 §7; ARCH.114). ⚠️ Конвенція імен ОДНА — мережева (`<NETWORK>_RPC_URL_FALLBACK_N`): вендорну
    # `INFURA_*` знято 2026-09-02 разом із заведенням keyless-фолбеків ([ARCH.114] ⚖️ founder:
    # PublicNode/dRPC як другий птах). Перейменування слота — СИНХРОННА правка з
    # `.env.example` (honesty-гейт `rpc_connection_pool_spec`) і з
    # `Security::Web3NetworkGuard::RPC_FALLBACK_URL_ENVS` (chain-вісь; пін у спеці гарда).
    # Keyless-URL живе в `env.clear` літералом — це не секрет, тож суддею його ЧЕЙНУ є
    # гард, а не `deploy_secret_scan` (той бачить лише суфікс `_RPC_URL`).
    #
    # ⛔ ОГОЛОШЕНА СТЕЛЯ: реєстр судить ПРИСУТНІСТЬ змінної, ніколи придатність URL.
    # `.env` розробника міг нести фолбек плейсхолдером (доти — `…infura.io/v3/YOUR_KEY`), і
    # каскад його візьме як живий провайдер — тобто «другий RPC є» може означати
    # «другий RPC оголошений». Це не регресія (`MintingRollbackService` читав ту саму
    # змінну так само), але тепер поведінка діє на ВСІХ money-сайтах, тож ціна названа
    # тут: детектора плейсхолдерів свідомо немає — він давав би шум на кожному dev-боксі,
    # а справжня перевірка живості другого провайдера є 👤-дією при заведенні акаунта.
    # 🔴 Наслідок для спек: `client_for` тепер чутливий до РЕАЛЬНОГО оточення там, де
    # раніше вистачало мока на `ENV.fetch` — приклади, що каскаду не судять, мусять
    # явно занулювати ці ключі (див. `before` у `rpc_connection_pool_spec`).
    NETWORK_FALLBACK_ENV_KEYS = {
      "ALCHEMY_POLYGON_RPC_URL" => %w[POLYGON_RPC_URL_FALLBACK_1 POLYGON_RPC_URL_FALLBACK_2].freeze,
      "CELO_RPC_URL" => %w[CELO_RPC_URL_FALLBACK_1 CELO_RPC_URL_FALLBACK_2].freeze
    }.freeze

    class << self
      # Повертає кешований клієнт для вказаного RPC URL env key.
      # Підтримує fallback cascade через fallback_env_keys.
      #
      # @param rpc_url_env_key [String] назва ENV-змінної з primary RPC URL
      # @param fallback [String, nil] резервний URL, якщо ENV-змінна відсутня (legacy)
      # @param fallback_env_keys [Array<String>] додаткові ENV-ключі для fallback cascade
      # @return [Eth::Client, Web3::ResilientClient]
      def client_for(rpc_url_env_key, fallback: nil, fallback_env_keys: [])
        thread_key = :"#{THREAD_KEY_PREFIX}#{rpc_url_env_key}"
        Thread.current[thread_key] ||= build_client(rpc_url_env_key, fallback, fallback_env_keys)
      end

      # 🔴 [ARCH.62] ПЕРЕНАКЛАДАЄ fee-політику на клієнта, ЯКОГО ВИДАВ ЦЕЙ ПУЛ.
      #
      # Вимір fee робиться на народженні клієнта, а клієнт кешується per-thread і
      # Sidekiq-потоки живуть до деплою — тобто число, поставлене раз, далі лише
      # старіє. Режим відмови детермінований і названий у шапці `Web3::FeePolicy`:
      # протухлий-занизький cap → tx не майниться → вічний `:sent` → rollback →
      # `manual_review`, тобто заблоковані кошти.
      #
      # 🔑 ЧОМУ НЕ TTL, і це не смак: TTL є ПРОКСІ для «щось змінилось», а тут
      # пускач відомий ТОЧНО — мить перед підписом транзакції. Кеш із пускачем
      # гасять на події, не за годинником (той самий присуд, що зняв TTL із
      # бейджа тривог); а TTL тут ще й вимагав би ЧИСЛА, якого не існує:
      # форми Polygon і Celo інверсні, тож спільного порога немає в принципі.
      #
      # 🏠 ДІМ — ПУЛ, бо ENV-ключ знає лише він: клієнт його не несе, а деривація
      # мережі через `client.chain_id` уже коштувала 78 падінь (шапка `FeePolicy`).
      # Ключ не зберігається окремо — він УЖЕ є в імені thread-local'а, тож нового
      # стану цей метод не заводить. ⛔ Не класти цю логіку у `FeePolicy`: вона
      # замкнула б цикл `pool → policy → pool`.
      #
      # ⚠️ Клієнт, що НЕ народився тут (тестовий дубль, інлайновий `Eth::Client`),
      # не впізнається — і тоді це чесний no-op, а не тиха підміна політики. Разом
      # із `FeePolicy::MEASURABLE_CLIENTS` це ДВА незалежні гарди проти того класу
      # регресії, що вже коштував 175 і 78 падінь сюїти.
      #
      # @return [Boolean] `true`, якщо клієнт пуловий і політику перенакладено
      def refresh_fee!(client)
        env_key = env_key_for(client)
        return false if env_key.nil?

        Web3::FeePolicy.apply!(client, env_key)
        true
      end

      # ENV-ключ, під яким ЦЕЙ обʼєкт лежить у кеші поточного потоку; `nil` — якщо
      # клієнт не з цього пулу. Порівняння саме `equal?` (тотожність), не `==`:
      # питання тут «чи це той самий обʼєкт», а не «чи вони рівні».
      def env_key_for(client)
        prefix = THREAD_KEY_PREFIX.to_s
        Thread.current.keys.each do |thread_key|
          name = thread_key.to_s
          next unless name.start_with?(prefix)
          return name.delete_prefix(prefix) if Thread.current[thread_key].equal?(client)
        end
        nil
      end

      # Скидає всі кешовані клієнти в поточному потоці.
      #
      # ⛔ **ЛИШЕ тести — продових викликачів НУЛЬ, і це не недогляд, а межа
      # механізму.** Спокуса зробити з нього лік від протухлого стану виникає
      # регулярно; вона не працює ЗА ПОБУДОВОЮ: `reset!` чистить `Thread.current`,
      # тож детектор, що його покличе (напр. `StuckSentTransactionSweeperWorker`),
      # скине ВЛАСНОГО клієнта й не торкнеться тих потоків, які тримають протухле
      # значення і мінтять. Для fee ця гілка й не потрібна — див. `refresh_fee!`.
      def reset!
        prefix = THREAD_KEY_PREFIX.to_s
        Thread.current.keys.each do |key|
          Thread.current[key] = nil if key.to_s.start_with?(prefix)
        end
      end

      private

      def build_client(rpc_url_env_key, fallback, fallback_env_keys)
        primary_url = fallback ? ENV.fetch(rpc_url_env_key, fallback) : ENV.fetch(rpc_url_env_key)

        # [ARCH.114] Явний kwarg лишається як OVERRIDE (нічого не ламає в наявних
        # сайтах), а за замовчуванням каскад береться з реєстру мережі — див. шапку
        # `NETWORK_FALLBACK_ENV_KEYS`. Саме це робить кеш-ключ чесним: для одного
        # env-ключа каскад один, хай хто кличе першим.
        cascade_keys = Array(fallback_env_keys).presence ||
                       NETWORK_FALLBACK_ENV_KEYS.fetch(rpc_url_env_key, [])

        # Збираємо всі доступні URLs для cascade
        all_urls = [ primary_url ]
        Array(cascade_keys).each do |key|
          url = ENV[key]
          all_urls << url if url.present?
        end

        all_urls.compact!
        all_urls.reject!(&:empty?)

        # Якщо тільки один URL — повертаємо звичайний Eth::Client (без overhead).
        # 🔴 Беремо `all_urls.first`, а НЕ `primary_url`: `reject!(&:empty?)` вище міг
        # щойно викинути порожній primary, і тоді вцілілим є саме фолбек. Форма
        # `Eth::Client.create(primary_url)` стояла тут до 2026-09-01 і робила каскад
        # ARCH.114 недієвим рівно в тому випадку, заради якого він побудований —
        # «primary порожній, фолбек живий»: розмір падав до 1, гілка брала порожній
        # рядок і гем валив `ArgumentError: Unable to detect client type!`, тобто
        # наявний живий ендпоінт не пробувався ЖОДНОГО разу. ⚠️ І це не кутовий
        # випадок: до 2026-09-02 Polygon мав у `NETWORK_FALLBACK_ENV_KEYS` рівно ОДИН фолбек,
        # і саме та конфігурація давала size==1; з двома гілка досяжна, коли порожні ОБИДВА. Порожній `all_urls` лишає стару гучну
        # помилку (`.to_s` → ""), і це навмисно — підключатись справді нема до чого.
        client =
          if all_urls.size <= 1
            Eth::Client.create(all_urls.first.to_s)
          else
            Web3::ResilientClient.new(all_urls)
          end

        # 🔴 [ARCH.62] FEE-ПОЛІТИКА НАКЛАДАЄТЬСЯ НА НАРОДЖЕННІ, І ЦЕ ДІМ, А НЕ
        # ЗРУЧНІСТЬ. Гем ставить fee у власному конструкторі (42.69/1.01 Gwei,
        # позначені в ньому ж `# Do not use.`) і ціни з ноди не питає ніколи —
        # тобто КОЖЕН клієнт народжується з чужою стелею, нижчою за ринок Polygon.
        # Тут вона перекривається один раз для всіх, хто цей клієнт візьме:
        # мережа відома СТАТИЧНО з `rpc_url_env_key`, тож ні RPC, ні `chain_id`
        # для цього не потрібні. `ResilientClient` каскадить присвоєння на кожного
        # свого клієнта власними сеттерами.
        Web3::FeePolicy.apply!(client, rpc_url_env_key)
        client
      end
    end
  end
end
