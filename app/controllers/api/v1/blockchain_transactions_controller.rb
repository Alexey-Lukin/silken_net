# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class BlockchainTransactionsController < BaseController
      # 📒 [UI.4] Дефолтне вікно аудит-леджера. ⚖️ founder 2026-08-18.
      #
      # 🔴 Це ВІДБІР записів, тож він легальний рівно як ОГОЛОШЕНИЙ видошукач: обидві
      # гілки друкують чинне вікно й дають вихід на повну історію (`?window=all`).
      # Без оголошення це був би тихий фільтр на аудит-поверхні — тобто «підмножина,
      # подана як вимір цілого» ([`ARCH.84`]-клас), і критерій місії («невідбирано»)
      # тут не декоративний.
      #
      # Число partition-shaped, не смакове: таблиця RANGE-партиційна ПОМІСЯЧНО, тож
      # 90 діб = ≤4 листи. Виміряно EXPLAIN'ом на реальній схемі, не виведено:
      # `Append` по 9 листах (cost 602.95) → по 5 (335.00); COUNT pagy 604.81 → 335.36.
      # ⚠️ `blockchain_transactions_default` не прунить НІКОЛИ — стоїть в обох планах,
      # тобто один лист є постійною підлогою (та сама межа, що `telemetry_logs_default`).
      # ⚠️ І вікно скорочує КІЛЬКІСТЬ листів, а не спосіб доступу: індексу з ведучим
      # `created_at` у таблиці немає, тож `Seq Scan`+`Sort` лишаються. Виграш у тому,
      # що вартість перестає масштабуватись ВІКОМ платформи й починає — попитом
      # організації (`04_04 §8.1а`).
      LEDGER_WINDOW_DAYS = 90

      # GET /blockchain_transactions
      # Глобальний аудит блокчейн-подій (Minting/Slashing) для Організації
      def index
        # [ARCH.98] One-Home: INNER JOIN через гаманець ховав cluster-sourced рядки
        # (Celo-винагорода, слеш останнього дерева) з АУДИТ-списку організації.
        # `:cluster` — друга координата провенансу, не дубль: рядки, заради яких
        # ARCH.98 і розширив скоуп, гаманця не мають, тож комірка джерела читає
        # саме її (N+1 інакше — виміряно).
        organization = acting_organization!

        @transactions = BlockchainTransaction
                          .for_organization(organization.id)
                          .includes(:cluster, wallet: :tree)
                          .order(created_at: :desc)

        # Вікно ставиться ДО фільтрів і до пагінації — воно звужує саму множину,
        # а не її зріз. AND на верхньому рівні: `for_organization` несе `OR`, але
        # той `OR` живе на `wallet_id`/`cluster_id`, тож партиційний відбір по
        # `created_at` він не знімає (виміряно EXPLAIN'ом — на відміну від
        # `unsettled_within`, де `created_at` сидить УСЕРЕДИНІ `OR` і прунінг гине).
        @window_start = ledger_window_start
        @transactions = @transactions.where(created_at: @window_start..) if @window_start

        # Фільтрація — параметри клієнта обмежуємо до enum-словника моделі,
        # інакше довільна строка ламає AR PG::InvalidTextRepresentation
        # (e.g. `?status=robert');drop table--`) та поглинає Sentry events.
        if params[:token_type].present?
          token_type_param = params[:token_type].to_s
          unless BlockchainTransaction.token_types.key?(token_type_param)
            render json: { error: I18n.t("flash.blockchain_transactions.invalid_token_type", value: token_type_param) }, status: :bad_request
            return
          end
          @transactions = @transactions.where(token_type: token_type_param)
        end

        if params[:status].present?
          status_param = params[:status].to_s
          unless BlockchainTransaction.statuses.key?(status_param)
            render json: { error: I18n.t("flash.blockchain_transactions.invalid_status", value: status_param) }, status: :bad_request
            return
          end
          @transactions = @transactions.where(status: status_param)
        end

        @pagy, @transactions = pagy(@transactions, limit: params.fetch(:limit, 50).to_i.clamp(1, 100))

        respond_to do |format|
          format.json do
            render json: {
              data: BlockchainTransactionBlueprint.render_as_hash(@transactions, view: :index),
              pagy: pagy_metadata(@pagy),
              # Оголошення видошукача й на машинному боці: `null` = повна історія.
              # Без нього та сама адреса віддавала б урізаний набір без жодної ознаки
              # того, що він урізаний — а це рівно те, проти чого писане вікно.
              window: { since: @window_start&.iso8601 }
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("blockchain_transactions.index_title"),
              component: BlockchainTransactions::Index.new(
                transactions: @transactions,
                pagy: @pagy,
                organization: organization,
                window_start: @window_start
              )
            )
          end
        end
      end

      # GET /blockchain_transactions/:id
      def show
        @transaction = find_transaction

        respond_to do |format|
          format.json do
            render json: BlockchainTransactionBlueprint.render(@transaction, view: :show)
          end
          format.html do
            render_dashboard(
              title: I18n.t("blockchain_transactions.show_title", id: @transaction.id),
              component: BlockchainTransactions::Show.new(transaction: @transaction)
            )
          end
        end
      end

      # --- ON-CHAIN ВЕРИФІКАЦІЯ (Lazy-Loaded Turbo Frame) ---
      # GET /blockchain_transactions/:id/on_chain
      def on_chain
        @transaction = find_transaction

        render BlockchainTransactions::OnChainFrame.new(transaction: @transaction), layout: false
      end

      private

      # `nil` = повна історія (єдиний вихід із вікна). Значення НЕ йде в SQL рядком —
      # воно лише обирає між двома гілками, тож класу `PG::InvalidTextRepresentation`,
      # проти якого стоять гарди `token_type`/`status` вище, тут не існує.
      #
      # Літерал береться з ДОМУ — компонента, що рендерить лінк виходу. Власна копія
      # тут розійшлася б із лінком ТИХО: сторінка й далі показувала б «показати всю
      # історію», а клік лишав би глядача у вікні. Будь-яке інше значення (описка,
      # ручний ввід, старий букмарк) падає у ВІКНО — fail-closed тут означає вужчий
      # зріз, тож битий параметр не перетворює аудит-сторінку на скан усіх партицій.
      # 🔴 Межа рівняється на ПОЧАТОК доби, і це не косметика: екран називає межу
      # ДАТОЮ, тож `.days.ago` з поточною годиною зробив би підпис брехливим —
      # рядки тієї самої дати, створені раніше за цю годину, у вибірку не потрапили б.
      # Заразом запит стає стабільним усередині доби, а не унікальним щохвилини.
      def ledger_window_start
        return nil if params[:window].to_s == BlockchainTransactions::Index::WINDOW_ALL

        LEDGER_WINDOW_DAYS.days.ago.beginning_of_day
      end

      # [PARTITION PRUNING / S6.16]: blockchain_transactions партиціоновано по
      # created_at, тож `?created_at=` звужує запит до однієї партиції. Форму
      # звуження НЕ пишемо тут — її дім `BlockchainTransaction.find_with_partition_pruning`
      # (⚡ PARTITION PRUNING INVARIANT, `04_01`: «контролери делегують сюди,
      # НЕ дублюють»). Рукописна копія, що стояла на цьому місці, звіряла
      # created_at ТОЧНОЮ рівністю — а ISO-8601 несе секундну точність проти
      # мікросекундної колонки, тож збігалась лише випадково; хелпер бере
      # 1-секундне вікно, яким PostgreSQL прунить так само до однієї партиції.
      # Битий/відсутній created_at хелпер сам відкочує в lookup без прунінгу.
      def find_transaction
        # [ARCH.98] Та сама резолюція, що в #index — інакше cluster-sourced
        # транзакція давала 404 за ПРЯМОЮ адресою на власні гроші організації.
        BlockchainTransaction
          .for_organization(acting_organization!.id)
          .includes(:cluster, wallet: :tree)
          .find_with_partition_pruning(params[:id], params[:created_at])
      end
    end
  end
end
