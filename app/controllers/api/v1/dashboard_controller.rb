# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class DashboardController < BaseController
      def index
        org = acting_organization!

        @stats = Rails.cache.fetch("dashboard_stats_org_#{org.id}", expires_in: 2.minutes) do
          # Агрегація Війська (scoped to organization)
          total_trees = org.trees.count
          active_trees = org.trees.active.count
          # [ARCH.84] One-Home `Cluster.health_coverage`. Доти тут стояла ДРУГА, вручну
          # продубльована копія формули `Organization#health_score` — з тим самим
          # `nil.to_f`, тобто «жоден кластер не виміряно» друкувалось як **0%**
          # життєздатності лісу. У кеш кладемо скаляри, не Struct.
          health = Cluster.health_coverage(org.clusters)

          # Агрегація енергії: середня напруга шини живлення MCU (мВ VDDA)
          # [ВИПРАВЛЕНО: Dashboard avg_voltage JOIN]:
          # Замість важкого JOIN на telemetry_logs (мільйони рядків за годину)
          # використовуємо вже денормалізовану колонку latest_voltage_mv із таблиці trees.
          # mark_seen! оновлює latest_voltage_mv при кожному пакеті телеметрії,
          # тому середнє по активних деревах відображає поточний стан флоту точніше.
          # [ARCH.84] ⛔ Без `|| 0`: `AVG` мовчки пропускає NULL, тож порожній набір
          # (жодне активне дерево ще не звітувало) віддає `nil` — і підстановка нуля
          # друкувала на ГОЛОВНІЙ сторінці «0mV», тобто браунаут-грейд вимір усього
          # флоту, якого ніхто не міряв. Форма зняття та сама, що в `Tree#supply_voltage_mv`.
          avg_voltage = org.trees.active.average(:latest_voltage_mv)
          growth_points = org.wallets.sum(:balance).to_f.round(4)

          {
            trees: {
              total: total_trees,
              active: active_trees,
              health_avg: health.average,
              clusters_measured: health.measured,
              clusters_total: health.total
            },
            # [ARCH.88] ДВІ різні величини, і плутати їх не можна: `growth_points` —
            # офчейн-бали, що ростуть від телеметрії; `minted_scc` — чинний monetary
            # supply організації (Σmints − Σburns) через One-Home `net_minted_supply`.
            # Ключ `total_scc` збережено як ДЕПРЕКОВАНИЙ аліас: він публікується назовні
            # і вже читається клієнтами, тож тихий ренейм тут заборонений так само, як у
            # `WalletBlueprint`. Один агрегат на 2-хвилинне вікно кешу — та сама ціна,
            # що в сусідніх лічильників цього ж блоку.
            economy: {
              # [UI.3] Аліас читає ТУ САМУ обчислену величину, не повторює агрегат:
              # доти два ключі з однаковим значенням били в БД двома однаковими
              # `SUM`, тоді як коментар вище стверджував «один агрегат». Дубль був
              # безкоштовний рівно доти, доки хтось не прочитає це як дозвіл.
              growth_points: growth_points,
              total_scc: growth_points,
              minted_scc: BlockchainTransaction.for_organization(org.id)
                                               .net_minted_supply(:carbon_coin).to_f.round(4)
            },
            security: {
              active_alerts: org.ews_alerts.unresolved.count
            },
            # 🔴 [ARCH.84/ARCH.99] `status` ЗНЯТО 2026-08-14 — це був уцілілий сайт
            # уже скасованого класу. `latest_voltage_mv` = мВ **VDDA**, а BQ25570
            # стабілізує цю шину на 3.3 В від VSTOR ≥ 3.4 В аж до 5.5 на іоністорі:
            # buck існує рівно щоб СХОВАТИ напругу сховища від MCU, тож шина за
            # конструкцією не несе інформації про запас енергії ([`04_01 §2`]).
            # Поріг «> 3300» тому не був «майже правильним» — він порівнював
            # величину з її ж регульованим номіналом, тобто питав «чи живий buck»
            # і друкував відповідь під іменем «запас енергії».
            #
            # ⚠️ Шкалу заряду знято присудом founder ще при ARCH.99 (`charge_percentage`,
            # `low_power?`, `VCAP_*`), і повернути її можна ЛИШЕ разом із живим
            # Vcap-каналом (FW.50). Цей ключ пережив ту хвилю, бо мав НУЛЬ споживачів:
            # UI читав `avg_voltage` і робив ВЛАСНУ копію того самого порога.
            #
            # `avg_voltage` лишається — канон називає його діагностичним (просідання
            # = близькість брауноуту), і це чесне сире число без вердикту.
            energy: {
              # ⚠️ `&.to_i`, не `.to_i`: голий виклик на `nil` віддає 0 — тобто
              # повертав би зняту щойно підстановку через кастинг.
              avg_voltage: avg_voltage&.to_i
            },
            global_onchain_carbon: fetch_global_onchain_carbon
          }
        end

        # Останні події для стрічки
        @recent_events = fetch_recent_events

        respond_to do |format|
          format.json { render json: @stats }
          format.html do
            # [UI.4] Вантажимо ЯВНО: компонент нижче рахує `.size` уже завантаженої
            # колекції, а знати ціле треба ТУТ — інакше `map_node_total` слав би
            # COUNT ще й на визначення `shown.size`.
            @map_trees = map_trees(org).to_a
            render_dashboard(
              title: I18n.t("dashboard.index_title"),
              component: Dashboard::Home.new(
                stats: @stats,
                events: @recent_events,
                trees: @map_trees,
                map_total: map_node_total(org, @map_trees),
                organization: org
              )
            )
          end
        end
      end

      private

      # Стеля першого рендеру геопросторової матриці. Leaflet тримає таку кількість
      # маркерів без кластеризації; понад неї сторінка показує ПІДМНОЖИНУ флоту —
      # свідомий борг, бо кластеризація маркерів = нова JS-залежність (→ 00_07 UI.4).
      # Живі оновлення ліміту не знають: broadcast_replace у ціль, якої нема в DOM,
      # Turbo тихо ігнорує.
      MAP_NODE_LIMIT = 500

      # Лише геолоковані дерева організації — і лише для html-гілки: JSON-споживач
      # мапи не рендерить, тож не платить за цей SELECT. N+1 тут немає за
      # побудовою: `Dashboard::MapNode` читає виключно колонки `trees`
      # (latitude/longitude/status + денормалізовані latest_stress_index,
      # latest_voltage_mv), жодної асоціації.
      # `order(:id)` не косметика: без нього `limit` віддає НЕДЕТЕРМІНОВАНУ
      # підмножину — понад стелею глядач бачив би різні дерева між
      # перезавантаженнями, а це виглядає як зникання вузлів, не як ліміт.
      def map_trees(org)
        org.trees.geolocated.order(:id).limit(MAP_NODE_LIMIT)
      end

      # 🔴 [UI.4] Скільки геолокованих вузлів організації Є НАСПРАВДІ — підстава під
      # числом, яке малює HUD. Без неї флот на 10 000 дерев друкувався «500», і стеля
      # `MAP_NODE_LIMIT` була видима лише тому, хто читав ЦЕЙ файл: сам екран її не
      # оголошував ніде, тобто підмножина подавалась як вимір цілого — той самий клас,
      # що [`ARCH.84`] закрив на кластерному середньому.
      # ⚡ COUNT платимо ЛИШЕ впершись у стелю: нижче неї показане й ціле рівні ЗА
      # ПОБУДОВОЮ, тож зайвий запит там купив би нуль інформації. Це та сама
      # арифметика, якою сусідній коментар боронив `.size` замість `.count`.
      def map_node_total(org, shown)
        shown.size < MAP_NODE_LIMIT ? shown.size : org.trees.geolocated.count
      end

      # [ВИПРАВЛЕНО: Sync RPC Trap]: Кешуємо GraphQL результат з TheGraph на 5 хвилин,
      # щоб не блокувати кожен запит дашборду на 2-10 секунд.
      def fetch_global_onchain_carbon
        Rails.cache.fetch("global_onchain_carbon", expires_in: 5.minutes) do
          Timeout.timeout(10) do
            TheGraph::QueryService.new.fetch_total_carbon_minted
          end
        end
      # 🔴 [ARCH.103] `nil`, а не `0`: недоступний subgraph — це «не виміряно», і
      # мовчазний нуль тут стверджував би, що протокол не намінтував нічого. ⚠️ Ключ
      # `global_onchain_carbon` живе в org-скоупленому `@stats`, хоча величина
      # PLATFORM-WIDE — сусіднє `minted_scc` поруч рахує ЦЮ організацію з нашої БД.
      # Три різні відповіді на близькі питання (org-DB · protocol-subgraph · контрактна)
      # → `00_07` ARCH.103; підпис кожної мусить називати, що саме вона рахує.
      rescue StandardError
        nil
      end

      def fetch_recent_events
        org = acting_organization!

        # Збираємо мікс з останніх алертів, транзакцій та реєстрацій (scoped to organization)
        [
          org.ews_alerts.includes(:cluster).order(created_at: :desc).limit(3),
          # [ARCH.98] One-Home — стрічка подій пропускала cluster-sourced рухи.
          # `:cluster` — не дубль гаманцевої гілки: cluster-sourced рядок гаманця не
          # має ЗА ПОБУДОВОЮ, і саме звідти `EventRow` бере джерело події.
          # [UI.3] `:sourceable` — не про приналежність, а про НАПРЯМОК і ГІЛКУ:
          # `EventRow` читає його, щоб відрізнити Etherisc-виплату, і без прелоаду
          # платив по запиту на рядок (виміряно: три спалення тягли ОДИН і той
          # самий контракт трьома запитами). Прелоад поліморфної асоціації бере
          # їх однією вибіркою на тип. ⚠️ Рядок із `sourceable_type IS NULL`
          # (звичайний мінт) запиту не робив ніколи — тобто дефект бачив лише той,
          # у чиїй стрічці є спалення чи страховка.
          BlockchainTransaction.for_organization(org.id)
                               .includes(:cluster, :sourceable, wallet: { tree: :cluster })
                               .order(created_at: :desc).limit(3),
          MaintenanceRecord.joins(:user)
                           .includes(:user)
                           .where(users: { organization_id: org.id })
                           .order(created_at: :desc).limit(3)
        ].flatten.sort_by(&:created_at).reverse.first(8)
      end
    end
  end
end
