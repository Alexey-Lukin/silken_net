# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class ContractsController < BaseController
      # Тільки автентифіковані користувачі (Інвестори бачать свої, Адміни — всі)

      # --- ПОРТФЕЛЬ КОНТРАКТІВ (Registry + Dashboard) ---
      # GET /contracts
      def index
        # [UI.8] `cluster: :ews_alerts` знято разом із `active_threats?`: після зняття
        # того ключа тривоги кластера тут не читає НІХТО — JSON віддає `cluster` лише
        # як `{id, name}`, а `Contracts::Index` бере `contract.cluster&.name`. Прелоад
        # без читача — це зайвий запит на кожен рендер списку.
        # [UI.7] Той самий гард, що вже стоїть у `#stats` нижче — і з тієї самої
        # підстави: `naas_contracts.organization_id` це `NOT NULL`, тож без нього
        # актор без організації діставав 200 із порожнім портфелем замість чесного
        # «немає контексту» (`04_03 §3.1`, політика (1)).
        acting_organization!
        scope = policy_scope(NaasContract).includes(:organization, :cluster)
        @pagy, @contracts = pagy(scope)

        # Агрегуємо дані для Phlex-дашборду, використовуючи твою логіку
        # ✅ [ARCH.103] ⚖️ Присуд founder: контрактну семантику ЗНЯТО на користь
        # КЛАСТЕРНОЇ. Величина знову вимірювана — і тепер справді виміряна: чиста
        # емісія кластерів, які покривають ці контракти (Σmints − Σburns через
        # One-Home `net_minted_supply`, той самий дім, що годує базу слешингу).
        #
        # ⚠️ Множина кластерів ДЕДУПЛІКОВАНА, і це несуче: кілька контрактів на одному
        # кластері співіснують одночасно (overlap не заборонений), тож сума «по
        # контрактах» порахувала б ту саму емісію N разів — рівно та переоцінка, через
        # яку контрактна деривація й виявилась невиконуваною.
        #
        # 🔴 Нуль ТУТ виміряний, а не фабрикований: агрегат виконався й підтверджених
        # рухів немає. Це протилежність тому, чим була `emitted_tokens` — колонка без
        # писача, чий нуль ніколи не був відповіддю на питання.
        @stats = {
          total_contracted: scope.sum(:total_value),
          total_minted: BlockchainTransaction.for_cluster(cluster_ids_for_scope(scope))
                                             .net_minted_supply(:carbon_coin),
          # [ОПТИМІЗАЦІЯ]: SQL агрегація замість перебору масиву в Ruby
          cluster_health: calculate_cluster_health_for_scope(scope)
        }

        respond_to do |format|
          format.json do
            render json: {
              data: @contracts.as_json(
                only: [ :id, :status, :total_value, :emitted_tokens ],
                include: {
                  cluster: { only: [ :id, :name ] },
                  organization: { only: [ :id, :name ] }
                }
              ),
              pagy: pagy_metadata(@pagy)
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("contracts.index_title"),
              component: Contracts::Index.new(contracts: @contracts, stats: @stats, pagy: @pagy,
                                              cluster_emissions: cluster_emissions_for(@contracts))
            )
          end
        end
      end

      # --- ДЕТАЛІ КРЕДИТНОЇ ЛІНІЇ (Deep Audit) ---
      # GET /contracts/:id
      def show
        @contract = find_contract(params[:id])
        @emission_history = BlockchainTransaction
          .joins(:wallet)
          .where(wallets: { organization_id: @contract.organization_id })
          .where(status: :confirmed)
          .order(created_at: :desc)
          .limit(10)

        respond_to do |format|
          format.json do
            render json: {
              contract: @contract.as_json,
              emission_history: @emission_history,
              # [ARCH.103] Три голі деференси `@contract.cluster.*` зведено в один дім,
              # спільний із HTML-панеллю застави. ⚠️ Гарда на «немає кластера» тут НЕМА
              # і не треба: `cluster_id` це `NOT NULL` у схемі ⊕ `belongs_to` без
              # `optional:` — стан недосяжний на обох шарах.
              backing_asset: backing_asset_for(@contract)
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("contracts.show_title", id: @contract.id),
              # [ARCH.103] Величина завжди є: кластер гарантований схемою, а нуль у ньому
              # ВИМІРЯНИЙ (агрегат виконався), тож стану «не виміряно» тут не буває.
              component: Contracts::Show.new(
                contract: @contract, history: @emission_history,
                cluster_emission: cluster_emission_for(@contract)
              )
            )
          end
        end
      end

      # --- ФІНАНСОВА АНАЛІТИКА (Повністю відновлено) ---
      # GET /contracts/stats
      def stats
        # [SEC.25 Ф2] Ручний гард «нема організації → 403» тут стояв доти й тепер
        # недосяжний: `acting_organization!` кидає раніше. Це не втрата, а вирівнювання
        # — 403 означає «тобі заборонено», тоді як насправді користувач просто без
        # організації, і решта дашборду відповідає на це 422 з `code: "no_organization"`.
        organization = acting_organization!
        cluster_health = calculate_cluster_health(organization)

        render json: {
          total_contracted: organization.naas_contracts.sum(:total_value),
          # ✅ [ARCH.103] Кластерна семантика (дім присуду — `#index` вище). Тут скоуп
          # ширший і чесніший за назву: `for_organization` бере ВСІ рухи орендаря, а не
          # лише кластери під контрактами — на цьому ендпоінті це і є питання, бо решта
          # його ключів теж орг-рівневі (`total_contracted`, `cluster_health`).
          total_tokens_minted: BlockchainTransaction.for_organization(organization.id)
                                                    .net_minted_supply(:carbon_coin).to_f.round(4),
          # [ARCH.84] Скаляр лишається тим, що описує клієнтський контракт (`07_01`,
          # шкала 0..1) — але тепер він **nullable**: `null` = не виміряно, і це не
          # те саме, що виміряний 0.0. Дві ноги покриття додано, бо саме вони не
          # дають прочитати середнє по одному кластеру як твердження про сто.
          cluster_health: cluster_health.average,
          clusters_measured: cluster_health.measured,
          clusters_total: cluster_health.total,
          attested_value_usd: calculate_attested_value(organization)
        }
      end

      private

      # [UI.7] Банг ПЕРЕД скоупленим `find`: без нього актор без організації діставав
      # `404` — тобто чужа за формою відповідь («такого контракту немає») на власне
      # питання про контекст. Гард розводить два різні стани, які скоуплений `find`
      # згортав в один.
      def find_contract(id)
        acting_organization!
        policy_scope(NaasContract).find(id)
      end

      # [ARCH.84] Обчислення — One-Home `Cluster.health_coverage`; шкала 0..1.
      #
      # ⛔ Голого `rescue → 1.0` тут БІЛЬШЕ НЕМА, і це не косметика: він ловив КОЖЕН
      # `StandardError` і віддавав «ідеальне здоров'я». Виміряно — з `PG::StatementInvalid`
      # усередині метод повертав `1.0`, тобто аварія БД звітувала інвесторові бездоганний
      # ліс. Виняток тепер іде драбиною `rescue_from` `BaseController`, як усе інше.
      def calculate_cluster_health(org)
        org.health_coverage
      end

      # [ARCH.84] Множина — КЛАСТЕРИ з-під цих контрактів, а не рядки контрактів.
      #
      # 🔴 Доти стояло `contracts.joins(:cluster).average(...)`, тобто середнє, зважене
      # за КІЛЬКІСТЮ КОНТРАКТІВ: кластер із трьома паперами важив утричі. Присуд дала не
      # смакова оцінка, а власний підпис картки — `sub:` цього `StatCard` каже
      # «**Avg Cluster Health**», тобто обіцяє середнє по кластерах. Виміряно на фікстурі
      # «здоровий кластер з 1 контрактом ⊥ мертвий з 3»: стара форма 0.3, чесна 0.5.
      # ⚠️ `unscope(:includes, :select)` несучий: викликач подає релацію з
      # `includes(cluster: :ews_alerts)`, і без зняття Rails перетворює її на
      # `eager_load` (LEFT JOIN), після чого `select(:cluster_id)` віддає не той
      # стовпець — підзапит тихо порожніє, а картка показує «не виміряно» на
      # виміряному фонді. Спіймано прикладом, не ревʼю.
      def calculate_cluster_health_for_scope(contracts)
        Cluster.health_coverage(Cluster.where(id: cluster_ids_for_scope(contracts)))
      end

      # [ARCH.103] ОДИН дім координати: обидва агрегати сторінки (здоровʼя й емісія)
      # питають ту саму множину кластерів. `unscope(:includes, :select)` тут не
      # косметика — без нього підзапит тягне eager-load і власний список стовпців,
      # тобто тихо порожніє (спіймано прикладом, не ревʼю).
      def cluster_ids_for_scope(contracts)
        contracts.unscope(:includes, :select).select(:cluster_id)
      end

      # [ARCH.103] Емісія кластерів ПОТОЧНОЇ СТОРІНКИ одним запитом — не всього скоупу:
      # рядкам потрібні рівно ті кластери, які рендеряться.
      #
      # 🔴 Хеш віддається РОЗРІДЖЕНИМ навмисно, і читач мусить це знати: кластер без
      # підтверджених рухів у ньому ВІДСУТНІЙ, але його емісія — виміряний НУЛЬ, а не
      # «не виміряно» (агрегат виконався). Тому вʼю робить `fetch(id, 0)`, а стан «не
      # виміряно» лишається рівно за контрактом БЕЗ кластера — там питання не має
      # субʼєкта. Плутати ці два стани і є [`ARCH.84`] навиворіт.
      def cluster_emissions_for(contracts)
        BlockchainTransaction.net_minted_by_cluster(
          contracts.filter_map(&:cluster_id).uniq, :carbon_coin
        )
      end

      # Одиничний сиблінг того самого питання.
      #
      # 🔴 Гарда на «контракт без кластера» тут НЕМА свідомо, і це вимір, а не сміливість:
      # стан неможливий на ОБОХ шарах — `cluster_id bigint NOT NULL` у схемі ⊕ `belongs_to
      # :cluster` без `optional:`. Отже «не виміряно» на цій поверхні недосяжне, і гілка
      # під нього була б мертвим кодом, який ще й обіцяє читачеві неіснуючий стан.
      def cluster_emission_for(contract)
        BlockchainTransaction.for_cluster(contract.cluster_id).net_minted_supply(:carbon_coin)
      end

      # Дзеркало HTML-панелі застави (`Contracts::Show#render_backing_asset_panel` робить
      # `return unless cluster`): без кластера блоку НЕМАЄ, а не «є з нулями».
      #
      # [UI.8] `active_threats?` — One-Home предиката, а НЕ інлайн-вираз: доти ця відповідь
      # несла ДВА пороги на одне питання — тут `unresolved.any?` (будь-яка severity), а
      # HTML-гілка ТОГО САМОГО екшена малювала вогник за `Cluster#active_threats?` (лише
      # critical). Ширший поріг ніколи не обирали свідомо — він приїхав латкою під виклик,
      # заведений тижнем раніше за сам метод; вужчий канонізований (`04_01 §Cluster`).
      def backing_asset_for(contract)
        cluster = contract.cluster

        {
          cluster_health: cluster.health_index,
          active_trees: cluster.active_trees_count,
          active_threats: cluster.active_threats?
        }
      end

      # 🔴 [ARCH.103] Найгостріший сайт класу в дереві: це була ДОЛАРОВА ОЦІНКА
      # ПОРТФЕЛЯ, і вона структурно дорівнювала нулю завжди — `sum(:emitted_tokens)`
      # по колонці без жодного писача, помножена на живу ціну з оракула. Тобто
      # єдиний правдивий множник у виразі створював враження виміру: ціна СПРАВДІ
      # тягнулась із DEX, тож число виглядало обчисленим, а не заповненим.
      # ⚠️ Оракул тут більше не смикаємо навмисно — зовнішній виклик заради
      # множення на невідоме є витратою без результату, і його тиша ще й читалась
      # би як «оцінка не працює», ховаючи справжню причину.
      # 🔓 Повертати разом із семантикою `emitted_tokens` (`00_07` ARCH.103).
      def calculate_attested_value(_org)
        nil
      end
    end
  end
end
