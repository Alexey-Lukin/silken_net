# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "eth"
require "bigdecimal"

module Treasury
  # =========================================================================
  # 💰 TREASURY MONITOR SERVICE (Централізований моніторинг Oracle Wallets)
  # =========================================================================
  # Перевіряє баланси ВСІХ живих Oracle-підписантів (per-signer після INF.22 key-спліту):
  #   - Polygon (MATIC) → MINTER (мінт SCC/SFC) + SLASHER (слешинг) + activation-gated
  #     aux (etherisc/puro/klima — дормантні шляхи пропускаються, поки ключ не інжектнуто)
  #   - Solana (SOL) → fee-payer мікро-винагород USDC
  #   - Celo (CELO) → community rewards cUSD
  #   - Ethereum L1 (ETH) → state root anchoring (щотижня)
  #
  # Повертає структурований звіт для Prometheus gauges та EWS alerts.
  # Підтримує пороги (мінімальні баланси) per-wallet.
  #
  # Використання:
  #   report = Treasury::MonitorService.call
  #   report.each { |r| puts "#{r[:network]}/#{r[:signer]}: #{r[:status]}" }
  # =========================================================================
  class MonitorService < ApplicationService
    # [INF.22] Один гаманець = один запис: після key-спліту на мережі живе КІЛЬКА
    # dedicated-підписантів (Polygon: minter/slasher + activation-gated aux) — моніторимо
    # газ КОЖНОГО живого signer'а, не легасі base-EOA (та retired повністю).
    # Пороги (min_balance) — fallback; runtime-значення через SystemParameter
    # (governance: ProtocolParameters.sol + ParameterSyncWorker).
    # activation_gated: ключ інжектиться Console'ю при активації шляху (06_04 §2.1) —
    # відсутній ENV = шлях дормантний → запис пропускається (без gauge і без алерту),
    # present = моніториться нарівні з required-набором.
    WALLETS = {
      polygon_minter: {
        network: "polygon", signer: "minter",
        env_rpc_key: "ALCHEMY_POLYGON_RPC_URL",
        env_private_key: "ORACLE_MINTER_PRIVATE_KEY",
        min_balance: 0.05, currency: "MATIC", decimals: 18,
        param_key: "oracle_min_balance_matic"
      },
      polygon_slasher: {
        network: "polygon", signer: "slasher",
        env_rpc_key: "ALCHEMY_POLYGON_RPC_URL",
        env_private_key: "ORACLE_SLASHER_PRIVATE_KEY",
        min_balance: 0.05, currency: "MATIC", decimals: 18,
        param_key: "oracle_min_balance_matic_slasher"
      },
      solana_fee_payer: {
        network: "solana", signer: "fee_payer",
        env_rpc_key: "SOLANA_RPC_URL",
        env_public_key: "SOLANA_FEE_PAYER_PUBKEY",
        min_balance: 0.05, currency: "SOL", decimals: 9,
        param_key: "oracle_min_balance_sol"
      },
      celo_rewards: {
        network: "celo", signer: "rewards",
        env_rpc_key: "CELO_RPC_URL",
        env_private_key: "ORACLE_CELO_PRIVATE_KEY",
        fallback_rpc: "https://alfajores-forno.celo-testnet.org",
        min_balance: 0.05, currency: "CELO", decimals: 18,
        param_key: "oracle_min_balance_celo"
      },
      ethereum_anchor: {
        network: "ethereum", signer: "anchor",
        env_rpc_key: "ALCHEMY_ETHEREUM_RPC_URL",
        env_private_key: "ETHEREUM_ANCHOR_PRIVATE_KEY",
        min_balance: 0.01, currency: "ETH", decimals: 18,
        param_key: "oracle_min_balance_eth"
      },
      polygon_etherisc: {
        network: "polygon", signer: "etherisc", activation_gated: true,
        env_rpc_key: "ALCHEMY_POLYGON_RPC_URL",
        env_private_key: "ORACLE_ETHERISC_PRIVATE_KEY",
        min_balance: 0.05, currency: "MATIC", decimals: 18,
        param_key: "oracle_min_balance_matic_etherisc"
      },
      polygon_puro: {
        network: "polygon", signer: "puro", activation_gated: true,
        env_rpc_key: "ALCHEMY_POLYGON_RPC_URL",
        env_private_key: "ORACLE_PURO_PRIVATE_KEY",
        min_balance: 0.05, currency: "MATIC", decimals: 18,
        param_key: "oracle_min_balance_matic_puro"
      },
      polygon_klima: {
        network: "polygon", signer: "klima", activation_gated: true,
        env_rpc_key: "ALCHEMY_POLYGON_RPC_URL",
        env_private_key: "ORACLE_KLIMA_PRIVATE_KEY",
        min_balance: 0.05, currency: "MATIC", decimals: 18,
        param_key: "oracle_min_balance_matic_klima"
      }
    }.freeze

    # Таймаут для окремого RPC-виклику (секунди)
    RPC_TIMEOUT = 10

    # [ARCH.62] Токен-типи, чий заминчений обсяг детектор стежить (SCC + SFC).
    MINT_TOKEN_TYPES = %w[carbon_coin forest_coin].freeze
    # Ковзне вікно виміру обсягу мінту — по МОМЕНТУ BROADCAST (`sent_at`), [INF.26].
    MINT_VOLUME_WINDOW = 1.hour
    # ⚠️ ЛИШЕ partition-prune: `sent_at` не є ключем партиціювання й не індексований,
    # тож без нижньої `created_at`-межі кожен прохід сканував би всі партиції. Число
    # НЕ семантичне — воно мусить лише надійно накривати найдовший шлях
    # `created_at → sent_at` (circuit-TTL + KYC-беклог + Sidekiq-ретраї), і тиждень
    # перекриває його з великим запасом.
    VOLUME_PRUNE_LOOKBACK = 7.days
    # Kredis-прапор inert circuit-break: детектор ставить per-token лише коли поріг увімкнено;
    # BlockchainMintingService читає його per token-group (ключ-prefix = One-Home там). TTL >
    # monitor-schedule → авто-release коли сплеск минув, авто-re-trip поки триває.
    MINT_CIRCUIT_TTL = 1.hour

    def perform
      results = WALLETS.filter_map do |wallet_key, wallet|
        if wallet[:activation_gated] && ENV[wallet[:env_private_key]].blank?
          Rails.logger.debug { "[Treasury] #{wallet_key} dormant (activation-gated, ключ відсутній) — skip" }
          next
        end

        check_balance(build_config(wallet))
      end

      # Оновлюємо Prometheus gauges
      update_metrics(results)

      # [G1/G2] Money-path limbo + drift видимість (той самий 15-хв прохід).
      update_money_path_metrics

      # [SEC.22] Флоат виплат — те, що СПРАВДІ обмежує вибух скомпрометованого
      # payout-ключа. Той самий прохід, бо предмет той самий (гарячі гаманці), а
      # окремий воркер додав би розклад без жодної нової відповіді.
      update_payout_float_metrics

      # [ARCH.62] Агрегатна mint-volume аномалія (той самий money-path прохід).
      detect_mint_volume_anomaly!

      # Генеруємо алерти для критичних балансів
      generate_alerts(results)

      # [ARCH.82] …і закриваємо ті, чия причина зникла. Порядок навмисний: спершу підняти
      # нові, тоді зняти одужалі — інакше гаманець, що впав і піднявся в межах одного
      # проходу, лишив би по собі закритий рядок замість жодного.
      resolve_recovered_balance_alerts!(results)

      results
    end

    private

    # 🔴 [SEC.22] ФЛОАТ ВИПЛАТ ≠ ГАЗ, і доти монітор міряв лише газ.
    #
    # Присуд SEC.22 (⚖️ 2026-08-29) прийняв резидентний Solana-ключ як bounded-blast
    # саме тому, що він не є mint-authority: він авторизує SPL-`transfer` із
    # передфінансованого ATA, тож стеля збитку = **флоат того ATA**. Але міряли ми
    # `getBalance` fee-payer'а, тобто SOL на газ — величину, яка про стелю збитку не
    # каже НІЧОГО. Підстава присуду не мала вимірювача.
    #
    # ⛔ Тиша тут не мовчазна: відсутній `SOLANA_FEE_PAYER_TOKEN_ACCOUNT` → просто
    # немає серії (гейдж не ставиться), а RPC-збій піднімає той самий
    # `TREASURY_CHECK_ERRORS_TOTAL`, що й решта проходу. Ставити `0` на збої
    # ЗАБОРОНЕНО: нуль флоату означає «гаманець порожній», і плутати його з «не змогли
    # прочитати» — рівно той дефект, який `ORACLE_BALANCE_RATIO` уже купив (INF.26).
    def update_payout_float_metrics
      ata = ENV["SOLANA_FEE_PAYER_TOKEN_ACCOUNT"]
      return if ata.blank?

      amount = fetch_spl_token_balance(ata)
      return if amount.nil?

      SilkenNet::Metrics::PAYOUT_FLOAT_BALANCE.set(amount, labels: { network: "solana", token: "USDC" })
    rescue StandardError => e
      SilkenNet::Metrics::TREASURY_CHECK_ERRORS_TOTAL.increment(
        labels: { network: "solana", signer: "fee_payer_ata", error_type: e.class.name }
      )
      Rails.logger.warn "[Treasury] payout-float read failed: #{e.class}: #{e.message}"
    end

    # `getTokenAccountBalance` віддає `{ amount, decimals, uiAmountString }`.
    # Беремо `uiAmountString` (десятковий рядок), бо сира `amount` — це base-units, а
    # питання гейджа людське: «скільки USDC лежить». `nil` = не змогли прочитати, і
    # викликач цей стан НЕ конвертує в нуль.
    def fetch_spl_token_balance(token_account)
      rpc_url = ENV["SOLANA_RPC_URL"]
      return nil if rpc_url.blank?

      response = Web3::HttpClient.post(rpc_url,
        body: { jsonrpc: "2.0", id: SecureRandom.uuid, method: "getTokenAccountBalance",
                params: [ token_account, { commitment: "confirmed" } ] },
        open_timeout: 10,
        read_timeout: RPC_TIMEOUT,
        service_name: "Solana"
      )

      value = response.parsed_body&.dig("result", "value")
      return nil if value.blank?

      value["uiAmountString"].presence&.to_f
    end

    # [G1] manual_review-глибина + limbo-locked + [G2] chain-audit drift → Prometheus.
    # Без цих gauge стан «кошти застрягли/розійшлися» невидимий до ручної перевірки.
    def update_money_path_metrics
      SilkenNet::Metrics::BLOCKCHAIN_MANUAL_REVIEW_DEPTH.set(
        BlockchainTransaction.status_manual_review.count
      )

      limbo = BlockchainTransaction
              .where(status: [ :sent, :manual_review ])
              .where("created_at < ?", 1.hour.ago)
              .sum(:locked_points)
      # [INF.26, переміряно 2026-08-25] `.to_i` тут БЕЗПЕЧНИЙ, і це не здогад: колонка
      # `blockchain_transactions.locked_points` — `bigint`, тож сума завжди ціла й
      # приведення є no-op. Підозра «зрізає дробові бали» стосувалась би `wallets.
      # locked_balance` (`numeric`), але сюди та шкала не заходить. ⛔ Не «лагодити» на
      # `.to_f`: правка стверджувала б дефект, якого немає, і наступний читач витратив
      # би прохід, шукаючи його причину.
      SilkenNet::Metrics::BLOCKCHAIN_LIMBO_LOCKED_TOTAL.set(limbo.to_i)

      # ChainAuditService кешується (5хв) — дешевий тут; critical=true теж читає gauge.
      SilkenNet::Metrics::CHAIN_AUDIT_DELTA.set(ChainAuditService.call.delta.to_f)

      # [INF.22] Filecoin archive-backlog семплиться ТУТ (15-хв money-path прохід), НЕ у
      # FilecoinReconcileWorker (repair — daily :48): in-process gauge обнуляється на restart
      # job-контейнера (deploy/OOM) → daily-семпл давав би ~24h сліпе вікно; 15-хв
      # cadence робить `min_over_time[6h]`-alert осмисленим. ВЕСЬ pending_archive (не LOOKBACK-
      # вікно) — post-LOOKBACK хвіст тримає плато, оператор бачить persistent-діру, не нуль.
      SilkenNet::Metrics::FILECOIN_UNARCHIVED_DEPTH.set(AuditLog.pending_archive.count)
      # [E.60 Фаза 1б] Незапінені архів-батчі (pending/build_failed) — той самий
      # freshness-паттерн, що й unarchived_depth вище.
      SilkenNet::Metrics::TELEMETRY_ARCHIVE_UNPINNED_DEPTH.set(
        TelemetryArchiveBatch.where(status: [ :pending, :build_failed ]).count
      )

      # [ARCH.66] Anchor stuck-:sent backlog — той самий 15-хв money-path прохід (freshness
      # проти restart-обнулення in-process gauge; sweeper-repair окремо hourly). `stuck_sent`
      # (scope: :sent AND updated_at > поріг) — здоровий anchor підтверджується за хвилини,
      # тож 0 у нормі, >0 лише реально-завислий (рахувати весь :sent пейджив би щотижня).
      SilkenNet::Metrics::ETHEREUM_ANCHOR_STUCK_SENT_DEPTH.set(EthereumAnchor.stuck_sent.count)
      SilkenNet::Metrics::ETHEREUM_ANCHOR_MANUAL_REVIEW_DEPTH.set(EthereumAnchor.status_manual_review.count)
    rescue StandardError => e
      # Спостережуваність не сміє валити monitor-цикл (баланси важливіші).
      Rails.logger.error "🛑 [Treasury] update_money_path_metrics: #{e.message}"
    end

    # [ARCH.62] Агрегатний mint-volume detector — комплемент, не заміна ex-post-clawback
    # (ARCH.53/SLASH-1 §3.3): обмежує blast-radius over-мінту у вікні детекції, поки clawback
    # (SE050 L2) не збудований. Gauge живий завжди (видимість обсягу); alert+circuit-break
    # активні ЛИШЕ коли SystemParameter-пороги увімкнено (inert-default — числа калібруються
    # з перших live-вікон, 👤). 05_02 §Модель довіри.
    def detect_mint_volume_anomaly!
      max_scc = SystemParameter.current(:mint_volume_hourly_max_scc, default: 0).to_f
      breaker_on = ActiveModel::Type::Boolean.new.cast(
        SystemParameter.current(:mint_circuit_breaker_enabled, default: false)
      )

      MINT_TOKEN_TYPES.each do |token_type|
        # 🔴 [ARCH.101] Напрямок ДЕРИВУЄТЬСЯ — інакше цей агрегат рахує спалення
        # мінт-обсягом (slash пишеться ДОДАТНИМ і теж `carbon_coin`, теж доходить до
        # `:sent`/`:confirmed`). ⚠️ Ціна не косметична й зворотна за знаком до
        # очікуваної: перебравши стелю, детектор смикає `trip_mint_circuit!` — тобто
        # ВЕЛИКЕ СПАЛЕННЯ вимикало б ЛЕГІТИМНИЙ мінтинг того самого токена. Дискримінатор
        # той самий, що в `net_minted_supply` — колонка `direction` [ARCH.95]; тримати
        # обидва боки в одному домі.
        # 🔴 [INF.26] Вікно ключується на BROADCAST (`sent_at`), не на `created_at`, і
        # дефект тут САМОРЕФЕРЕНТНИЙ — це його найгірша властивість. Розбіжність
        # моменту наміру й моменту відправки виникає рівно тоді, коли tx довго стояла
        # `:pending`, а НАЙЧАСТІША причина цього — САМ ЦЕЙ ДЕТЕКТОР:
        # `trip_mint_circuit!` тримає батч `:pending` із TTL `MINT_CIRCUIT_TTL` = 1 год,
        # тобто рівно ширину вікна. Коли прапор спливає, пул зливається в мемпул
        # рядками, ЯКІ ВЖЕ СТАРШІ за годину — тож дренаж після власного HOLD'у детектор
        # не бачив узагалі. Те саме для KYC-беклогу і Sidekiq-ретраїв.
        # Прецедент форми — `StuckSentTransactionSweeperWorker` (той самий присуд:
        # «поріг ключується на момент broadcast, бо reset-to-pending тримає СТАРИЙ
        # `created_at`», ARCH.52 trap).
        #
        # ⚠️ Нижня `created_at`-межа семантично НЕ ПОТРІБНА — вона тут ЛИШЕ прунить
        # партиції: `sent_at` не є ключем партиціювання й не має індексу, тож без неї
        # це seq-scan усіх партицій щочверть години. Стеля оголошена: мінт, відправлений
        # у вікно, але СТВОРЕНИЙ раніше за `VOLUME_PRUNE_LOOKBACK`, у лік не потрапить —
        # це недосяжно для живого тракту (ретраї обмежені), і чесніше за повний скан.
        volume = BlockchainTransaction
                 .where(token_type: token_type, status: [ :sent, :confirmed ])
                 .where(direction: :mint)
                 .where(sent_at: MINT_VOLUME_WINDOW.ago..)
                 .where("created_at >= ?", VOLUME_PRUNE_LOOKBACK.ago) # [prune-only, не семантика]
                 .sum(:amount).to_f
        SilkenNet::Metrics::MINT_VOLUME_WINDOW_SCC.set(volume, labels: { token_type: token_type })

        # Поріг 0 = detector-off (gauge все одно живий) — не алертимо, поки 👤 не налаштує.
        # [ARCH.82] …але спершу закриваємо те, що вже висить: причина спостережувана в цьому
        # ж проході, а рядок безкластерний, тож жодна людина закрити його не може.
        unless max_scc.positive? && volume > max_scc
          resolve_mint_volume_alert!(token_type, volume, max_scc)
          next
        end

        Rails.logger.warn "🚨 [ARCH.62] Mint-volume аномалія: #{token_type} " \
                          "#{volume.round(2)} SCC за #{MINT_VOLUME_WINDOW.inspect} (поріг #{max_scc.round(2)})."
        # Dedup: sustained breach інакше плодив би critical-алерт щоцикл (~4/год/токен) → флуд
        # ops-черги. Один активний mint-volume-алерт на token_type достатньо.
        unless active_mint_volume_alert?(token_type)
          EwsAlert.create(
            alert_type: :system_fault,
            severity: :critical,
            message_key: "mint_volume_anomaly",
            message_params: { token_type: token_type, volume: volume.round(2),
                              window: MINT_VOLUME_WINDOW.inspect, ceiling: max_scc.round(2) }
          )
        end
        # Inert circuit-break: per-token HOLD нових mint-батчів, поки людина не звірить причину.
        trip_mint_circuit!(token_type, volume, max_scc) if breaker_on
      end
    rescue StandardError => e
      # Детектор — спостережуваність; не валимо monitor-цикл (баланси важливіші).
      Rails.logger.error "🛑 [Treasury] detect_mint_volume_anomaly!: #{e.message}"
    end

    # Активний mint-volume-алерт для цього token_type уже висить? (dedup — див. detector).
    # 🔴 Раніше тут стояв `message LIKE "Mint-volume anomaly …"` — тобто РЕНДЕРЕНИЙ
    # ТЕКСТ виконував роль ключа дедупу. Переведення прози на `message_key` без
    # цієї правки зламало б дедуп ТИХО: запит перестав би щось знаходити, і
    # critical-алерт сипався б щоцикла (~4/год/токен) у ops-чергу. Тепер ключ —
    # це ключ, а token_type — параметр, і `sanitize_sql_like` більше не потрібен
    # (нема LIKE-патерну, є рівність).
    def active_mint_volume_alert?(token_type)
      EwsAlert.where(alert_type: :system_fault, status: :active, message_key: "mint_volume_anomaly")
              .where("message_params ->> 'token_type' = ?", token_type)
              .exists?
    end

    # [ARCH.82] Закриває mint-volume-алерт, коли причина зникла. Дзеркало
    # `TreeStalenessSweepWorker#resolve_returned_trees` — ⚖️ founder 2026-08-14: для
    # безкластерних алертів шлях закриття АВТОМАТИЧНИЙ, а не людський, бо жодна орг-поверхня
    # їх не бачить (`Organization has_many :ews_alerts, through: :clusters` = INNER JOIN).
    #
    # 🔴 Асиметрія, яку це прибирає, була в самому файлі: Kredis-запобіжник має
    # `MINT_CIRCUIT_TTL` і сам відпускається, коли сплеск минув, — а алерт про той самий
    # сплеск не відпускався НІКОЛИ. Тобто механізм уже вмів помічати одужання; не вмів
    # лише його ЗАПИСАТИ.
    #
    # Дві причини закриття свідомо розрізняються в нотатці: «обсяг повернувся під стелю» —
    # це одужання, а «детектор вимкнули» — ні. Друге все одно закриваємо: алерт від
    # вимкненого детектора не має жодного шляху зникнути, і саме він накопичувався б.
    def resolve_mint_volume_alert!(token_type, volume, max_scc)
      alert = EwsAlert.unresolved
                      .where(alert_type: :system_fault, message_key: "mint_volume_anomaly")
                      .where("message_params ->> 'token_type' = ?", token_type)
                      .first
      return if alert.nil?

      # [I18N.1] Дві причини закриття — ДВА ключі (одужання ⊥ детектор вимкнули),
      # не булевий параметр: в іншій мові це різні речення, і саме ця пара
      # розрізняє «усунуто» від «безпредметно» в доказовому записі.
      if max_scc.positive?
        alert.resolve!(key: "mint_volume_recovered",
                       params: { token_type: token_type,
                                 volume: volume.round(2), max: max_scc.round(2) })
      else
        alert.resolve!(key: "mint_volume_detector_disabled")
      end
      Rails.logger.info "✅ [ARCH.82] mint_volume_anomaly (#{token_type}) закрито автоматично " \
                        "(#{max_scc.positive? ? 'recovered' : 'detector disabled'})."
    end

    # Ставить inert per-token Kredis-прапор, який BlockchainMintingService читає per token-group →
    # HOLD цих mint-батчів у :pending (re-runnable) до TTL-expiry/reset. Reset — console (.remove).
    def trip_mint_circuit!(token_type, volume, max_scc)
      Kredis.flag("#{BlockchainMintingService::MINT_CIRCUIT_FLAG_PREFIX}#{token_type}").mark(expires_in: MINT_CIRCUIT_TTL)
      Rails.logger.error "🛑 [ARCH.62] Mint circuit-breaker TRIPPED (#{token_type}: #{volume.round(2)} > #{max_scc.round(2)}) — " \
                         "нові #{token_type} mint-батчі тримаються :pending до TTL-expiry/reset."
    end

    # [INF.22] Resolves the wallet entry into a runtime config with governance-aware thresholds.
    # SystemParameter.current reads from 24h cache → no DB hit on every monitor cycle.
    def build_config(wallet)
      min_balance = (SystemParameter.current(wallet[:param_key], default: wallet[:min_balance]) || wallet[:min_balance]).to_f
      min_balance_wei = (BigDecimal(min_balance.to_s) * 10**wallet[:decimals]).to_i

      wallet.merge(min_balance_wei: min_balance_wei)
    end

    # Перевіряє баланс одного Oracle-гаманця (network+signer).
    # Повертає Hash з результатом перевірки.
    def check_balance(config)
      balance = fetch_balance(config)

      min_threshold = config[:min_balance_wei].to_i
      ratio = min_threshold.positive? ? (balance.to_f / min_threshold) : 0.0
      status = balance >= min_threshold ? :healthy : :critical

      {
        network: config[:network],
        signer: config[:signer],
        currency: config[:currency],
        balance_raw: balance,
        balance_human: humanize_balance(balance, config[:decimals]),
        min_threshold_raw: min_threshold,
        min_threshold_human: humanize_balance(min_threshold, config[:decimals]),
        ratio: ratio.round(2),
        status: status
      }
    rescue StandardError => e
      SilkenNet::Metrics::TREASURY_CHECK_ERRORS_TOTAL.increment(
        labels: { network: config[:network], signer: config[:signer], error_type: e.class.name }
      )

      Rails.logger.error "🛑 [Treasury] #{config[:network]}/#{config[:signer]} balance check failed: #{e.message}"

      {
        network: config[:network],
        signer: config[:signer],
        currency: config[:currency],
        balance_raw: nil,
        balance_human: "ERROR",
        min_threshold_raw: config[:min_balance_wei].to_i,
        min_threshold_human: humanize_balance(config[:min_balance_wei].to_i, config[:decimals]),
        ratio: 0.0,
        status: :error,
        error: e.message.truncate(200)
      }
    end

    # Отримує баланс гаманця (диспетч за мережею)
    def fetch_balance(config)
      Timeout.timeout(RPC_TIMEOUT) do
        case config[:network]
        when "solana" then fetch_solana_balance(config)
        else fetch_evm_balance(config)
        end
      end
    end

    # EVM-мережі (Polygon, Celo, Ethereum): eth_getBalance через eth gem
    def fetch_evm_balance(config)
      client = if config[:fallback_rpc]
        Web3::RpcConnectionPool.client_for(config[:env_rpc_key], fallback: config[:fallback_rpc])
      else
        Web3::RpcConnectionPool.client_for(config[:env_rpc_key])
      end

      # ⛔ [SEC.17] СВІДОМО не через `Web3::OracleSigner.for` — цей прохід світить УСІ
      # сім гаманців, включно з дормантними aux-підписантами (etherisc/puro/klima), чиї
      # ключі на деплой-поверхні відсутні за побудовою. `OracleSigner` б'є `KeyError`
      # (fail-loud — правильно на money-шляху), а тут відсутній ключ = «гаманець не
      # активований», не збій: `ENV[..]` + blank-гард лишають 0 і свіп триває.
      private_key = ENV[config[:env_private_key]]
      return 0 if private_key.blank?

      client.get_balance(Web3::LocalEnvSigner.new(private_key).address)
    end

    # Solana: getBalance через JSON RPC
    def fetch_solana_balance(config)
      # [OPS.37] Chain axis, not `Rails.env.production?` — the hardcoded fallback below is
      # Devnet, so refusing it is only right on a slot that declares itself `mainnet`.
      if ENV[config[:env_rpc_key]].blank? && Security::Web3NetworkGuard.chain_env(ENV) == "mainnet"
        Rails.logger.warn "[Treasury] #{config[:env_rpc_key]} not set on a mainnet slot — Solana balance check skipped"
        return 0
      end
      rpc_url = ENV.fetch(config[:env_rpc_key], "https://api.devnet.solana.com")
      fee_payer = ENV[config[:env_public_key]]
      return 0 if fee_payer.blank?

      payload = {
        jsonrpc: "2.0",
        id: SecureRandom.uuid,
        method: "getBalance",
        params: [ fee_payer, { commitment: "confirmed" } ]
      }

      response = Web3::HttpClient.post(rpc_url,
        body: payload,
        open_timeout: 10,
        read_timeout: RPC_TIMEOUT,
        service_name: "Solana"
      )

      response.parsed_body&.dig("result", "value").to_i
    end

    # Оновлює Prometheus gauges з поточними балансами
    def update_metrics(results)
      results.each do |result|
        labels = { network: result[:network], signer: result[:signer] }

        if result[:balance_raw]
          SilkenNet::Metrics::ORACLE_BALANCE.set(result[:balance_raw], labels: labels)
        end

        # 🔴 [INF.26] Той САМИЙ гард, що в сусіда — і асиметрія між ними була доказом
        # дефекту, а не стилю. `check_balance`'s `rescue` віддає `balance_raw: nil` разом
        # із `ratio: 0.0`, тож незахищений `set` писав нуль, НЕВІДРІЗНИМИЙ від «оракул
        # справді порожній»: один RPC-таймаут пейджив ДВОМА правилами
        # (`sn-alert-oracle-balance-critical` P0 + `…-low` P2) на гаманці, який може бути
        # повний. Класична підміна виміру — показник хибний ЧЕРЕЗ ПРИЛАД.
        #
        # ⊕ Друга гілка того ж нуля: `ratio` рахується як `0.0` і коли поріг не
        # налаштований (`min_threshold.zero?`) — тобто «не сконфігуровано» теж читалось
        # як «критично». Обидва стани тепер МОВЧАТЬ на цьому gauge.
        #
        # ⚠️ Ціна названа: при збої gauge завмирає на останньому значенні, а не падає в
        # нуль. Саме тому «не змогли прочитати» дістає ВЛАСНИЙ голос — лічильник
        # `TREASURY_CHECK_ERRORS_TOTAL` (інкрементиться в тому ж `rescue`) і алерт на
        # нього; інакше ми проміняли б гучну брехню на тиху.
        next unless result[:balance_raw] && result[:min_threshold_raw].to_i.positive?

        SilkenNet::Metrics::ORACLE_BALANCE_RATIO.set(result[:ratio], labels: labels)
      end
    end

    # Генерує EWS alerts для критичних балансів
    def generate_alerts(results)
      critical_results = results.select { |r| r[:status] == :critical }
      return if critical_results.empty?

      critical_results.each do |result|
        Rails.logger.warn "🚨 [Treasury] CRITICAL: #{result[:network]}/#{result[:signer]} Oracle balance " \
                          "#{result[:balance_human]} #{result[:currency]} " \
                          "below threshold #{result[:min_threshold_human]} #{result[:currency]} " \
                          "(ratio: #{result[:ratio]}x)"

        # Dedup — дзеркало `active_mint_volume_alert?` у цьому ж файлі, і асиметрія була
        # реальна: сусідній детектор мав гард із порахованою ціною («~4/год/токен → флуд
        # ops-черги»), а цей не мав жодного. Порожній гаманець тримається годинами, крон
        # ходить `*/15`, підписантів вісім — тобто до 32 нових `active` critical-рядків на
        # годину, безстроково. Ідентичність тут — ПАРА (мережа, підписант): різні
        # підписанти порожніють незалежно, тож глушити їх одним рядком не можна.
        next if active_oracle_balance_alert?(result[:network], result[:signer])

        # Створюємо EwsAlert для оперативного реагування (system_fault — загальний тип для інфраструктурних проблем)
        EwsAlert.create(
          alert_type: :system_fault,
          severity: :critical,
          message_key: "oracle_balance_low",
          message_params: { network: result[:network], signer: result[:signer],
                            balance: result[:balance_human], currency: result[:currency],
                            min_threshold: result[:min_threshold_human], ratio: result[:ratio] }
        )
      end
    end

    # [ARCH.82] Закриває oracle-balance-алерти пар, які цього проходу вже НЕ критичні.
    # ⚖️ founder 2026-08-14: безкластерний алерт закривається автоматично, бо людського
    # шляху до нього не існує — орг-поверхні його не бачать за побудовою.
    #
    # Ключ одужання — той самий, що й ключ дедупу: ПАРА (мережа, підписник). Інакше
    # поповнення одного гаманця гасило б тривогу про сім інших.
    #
    # ⚠️ Стеля названа: `results` містить лише гаманці, ПЕРЕВІРЕНІ цього проходу, тож
    # activation-gated гаманець, у якого зняли ключ, випадає з переліку — його алерт
    # лишиться висіти. Це свідомо: «ключ зник» не означає «баланс поповнено», і мовчазно
    # закривати тривогу про гаманець, якого ми більше не бачимо, було б гірше за висячий
    # рядок. Спостережуваність тієї підмножини тримає Grafana (`oracle_balance_ratio`).
    def resolve_recovered_balance_alerts!(results)
      recovered = results.reject { |r| r[:status] == :critical }
      return if recovered.empty?

      recovered.each do |result|
        alert = EwsAlert.unresolved
                        .where(alert_type: :system_fault, message_key: "oracle_balance_low")
                        .where("message_params ->> 'network' = ? AND message_params ->> 'signer' = ?",
                               result[:network].to_s, result[:signer].to_s)
                        .first
        next if alert.nil?

        alert.resolve!(
          key: "oracle_balance_recovered",
          params: { network: result[:network].to_s, signer: result[:signer].to_s,
                    balance: result[:balance_human], threshold: result[:min_threshold_human],
                    currency: result[:currency] }
        )
        Rails.logger.info "✅ [ARCH.82] oracle_balance_low (#{result[:network]}/#{result[:signer]}) " \
                          "закрито автоматично — баланс відновлено."
      end
    end

    # Активний oracle-balance-алерт для цієї пари вже висить? (dedup — див. `generate_alerts`).
    # Ключуємось на `message_key` + двох параметрах, НІКОЛИ на рендереному тексті: та сама
    # пастка, що вже ламала дедуп сусіда тихо — запит просто переставав щось знаходити.
    def active_oracle_balance_alert?(network, signer)
      EwsAlert.where(alert_type: :system_fault, status: :active, message_key: "oracle_balance_low")
              .where("message_params ->> 'network' = ? AND message_params ->> 'signer' = ?",
                     network.to_s, signer.to_s)
              .exists?
    end

    # Конвертує wei/lamports у людський формат
    def humanize_balance(raw_balance, decimals)
      format("%.6f", (BigDecimal(raw_balance.to_s) / 10**decimals))
    end
  end
end
