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
        # 🔴 [ARCH.103] `total_minted` — `nil`, і це ВИМІР, а не збій. Джерело
        # (`naas_contracts.emitted_tokens`) має схемний `DEFAULT 0.0` і НУЛЬ писачів,
        # тож сума завжди повертала впевнений `0`, невідрізнимий від чесного «ще не
        # намінчено». ⛔ Дротувати писача сьогодні НЕМА КУДИ: кластер може нести
        # кілька контрактів ОДНОЧАСНО (overlap не заборонений), а mint-рядок не має
        # жодного посилання на контракт — тобто величина не має визначення, а не
        # лише реалізації. Тригер повернення — присуд про семантику (`00_07` ARCH.103).
        @stats = {
          total_contracted: scope.sum(:total_value),
          total_minted: nil,
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
              component: Contracts::Index.new(contracts: @contracts, stats: @stats, pagy: @pagy)
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
              backing_asset: {
                cluster_health: @contract.cluster.health_index,
                active_trees: @contract.cluster.active_trees_count,
                # [UI.8] One-Home предиката, а НЕ інлайн-вираз: доти ця відповідь
                # несла ДВА пороги на одне питання — тут `unresolved.any?` (будь-яка
                # severity), а HTML-гілка ТОГО САМОГО екшена малювала вогник за
                # `Cluster#active_threats?` (лише critical). Ширший поріг ніколи не
                # обирали свідомо — він приїхав латкою під виклик, заведений тижнем
                # раніше за сам метод; вужчий канонізований (`04_01 §Cluster`).
                active_threats: @contract.cluster.active_threats?
              }
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("contracts.show_title", id: @contract.id),
              component: Contracts::Show.new(contract: @contract, history: @emission_history)
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
          # [ARCH.103] `nil` = не виміряно (дім рішення — `#index` вище).
          total_tokens_minted: nil,
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
        cluster_ids = contracts.unscope(:includes, :select).select(:cluster_id)
        Cluster.health_coverage(Cluster.where(id: cluster_ids))
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
