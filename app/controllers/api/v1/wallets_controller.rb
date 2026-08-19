# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "csv"

module Api
  module V1
    class WalletsController < BaseController
      include CsvStreamable

      # --- ЗАГАЛЬНИЙ ОГЛЯД СКАРБНИЦІ (The Treasury Matrix) ---
      # GET /wallets
      # [UI.7] Гаманець — тенантний ресурс, тож актор без організації дістає те саме
      # `422 no_organization`, що й решта дашборда (`04_03 §3.1`, політика (1)).
      # Доти цей екшен віддавав 200 із ПОРОЖНІМ реєстром над живим флотом — тобто
      # був невідрізнимий від організації, що справді не має жодного гаманця.
      def index
        acting_organization!
        scope = policy_scope(Wallet).includes(:organization, :tree)
        @pagy, @wallets = pagy(scope)

        respond_to do |format|
          format.json do
            render json: {
              data: WalletBlueprint.render_as_hash(@wallets),
              pagy: pagy_metadata(@pagy)
            }
          end
          format.html do
            # [ARCH.88] `balance` напряму: аліас лише перейменовував бали в монету,
            # а підсумок реєстру — сума БАЛІВ, і підписується він тепер як GP.
            total_liquidity = scope.sum(:balance)
            render_dashboard(
              title: I18n.t("wallets.index_title"),
              component: Wallets::Index.new(wallets: @wallets, pagy: @pagy, total_liquidity: total_liquidity)
            )
          end
        end
      end

      # --- ДЕТАЛІ ГАМАНЦЯ (On-Chain Audit) ---
      # GET /wallets/:id
      def show
        acting_organization!
        @wallet = Wallet.find(params[:id])
        authorize @wallet
        @pagy_tx, @transactions = pagy(@wallet.blockchain_transactions.order(created_at: :desc), limit: 50)

        respond_to do |format|
          format.json do
            render json: {
              data: WalletBlueprint.render_as_hash(@wallet, view: :show),
              transactions: BlockchainTransactionBlueprint.render_as_hash(@transactions, view: :index),
              pagy: pagy_metadata(@pagy_tx)
            }
          end
          format.html do
            render_dashboard(
              title: I18n.t("wallets.show_title", address: @wallet.crypto_public_address&.first(8)),
              component: Wallets::Show.new(wallet: @wallet, transactions: @transactions, pagy: @pagy_tx)
            )
          end
        end
      end

      # --- БАЛАНС ГАМАНЦЯ (Lazy-Loaded Turbo Frame) ---
      # GET /wallets/:id/balance
      def balance
        acting_organization!
        @wallet = Wallet.find(params[:id])
        authorize @wallet

        respond_to do |format|
          format.json do
            render json: { data: WalletBlueprint.render_as_hash(@wallet, view: :balance) }
          end
          format.html do
            render Wallets::BalanceFrame.new(wallet: @wallet), layout: false
          end
        end
      end

      # --- СТАТУС ТРАНЗАКЦІЇ (I18N.2 · клас 2 «viewer-driven pull») ---
      # GET /wallets/:wallet_id/transactions/:id/status
      #
      # Turbo-frame тягне СВІЙ фрагмент власним запитом — тобто вже з локаллю
      # глядача (`LocaleSettable` тут відпрацював) і його ж авторизацією. Саме це
      # дозволяє броадкасту рядка не нести жодного перекладеного слова.
      #
      # ⚠️ Авторизація йде по ГАМАНЦЮ й тим самим предикатом, що сторінка
      # (`transaction_status? = show?`). Це свідома відмова від власного правила
      # для транзакції: `WalletPolicy#show?` приймає АБО `wallet.organization_id`,
      # АБО `wallet.tree.cluster.organization_id`, а сусідній `find_transaction`
      # у `BlockchainTransactionsController` скоупить лише другим шляхом — тобто
      # два правила вже розходяться, і копія тут дала б сторінку, що рендериться,
      # з комірками, які вічно пульсують на 404.
      #
      # ⚠️ `created_at` у запиті — не оздоблення, а ключ партиції: таблиця
      # RANGE-партиційована, і без нього пошук сканує ВСІ партиції. Хелпер моделі
      # сам тримає 1-секундне вікно (ISO-8601 має секундну точність, колонка —
      # мікросекундну) і fail-safe на кривому форматі.
      def transaction_status
        acting_organization!
        @wallet = Wallet.find(params[:wallet_id])
        authorize @wallet

        transaction = @wallet.blockchain_transactions
                             .find_with_partition_pruning(params[:id], params[:created_at])

        # ⚠️ Фрейм у відповіді — БЕЗ `src`. Не «щоб не було циклу»: Turbo ловить
        # self-referencing src, кидає в консоль `references itself` і лишає фрейм
        # ПОРОЖНІМ — тобто ціна помилки не трафік, а назавжди порожня комірка й
        # тиха помилка, якої ніхто не побачить.
        render Wallets::TransactionStatusFrame.new(tx: transaction), layout: false
      end

      # --- ЛЕДЖЕР ГАМАНЦЯ (CSV-вивантаження) ---
      # GET /wallets/:id/ledger.csv
      #
      # [UI.7] Дротування кнопки «Export CSV» за reports-патерном (`format.csv` +
      # `stream_csv` зі спільного концерну). Авторизація — та сама пара, що на
      # сторінці (`acting_organization!` + `WalletPolicy#ledger? = show?`): CSV — та
      # сама грошова поверхня, лише в іншому форматі, і власного правила
      # тенантності вона не заводить.
      def ledger
        acting_organization!
        @wallet = Wallet.find(params[:id])
        authorize @wallet

        respond_to do |format|
          format.csv do
            stream_csv("wallet_ledger_#{@wallet.id}_#{Date.current}.csv") do |yielder|
              generate_ledger_csv_enum(@wallet).each { |row| yielder << row }
            end
          end
        end
      end

      # --- БЛОКЧЕЙН ІДЕНТИЧНІСТЬ (Lazy-Loaded Turbo Frame) ---
      # GET /wallets/:id/metadata
      def metadata
        acting_organization!
        @wallet = Wallet.find(params[:id])
        authorize @wallet

        respond_to do |format|
          format.json do
            render json: { data: WalletBlueprint.render_as_hash(@wallet, view: :metadata) }
          end
          format.html do
            render Wallets::MetadataFrame.new(wallet: @wallet), layout: false
          end
        end
      end

      private

      # [UI.7] Аудиторське вивантаження рухів гаманця. Що в рядку — і чому саме це:
      #   · Direction — ДЕРИВАЦІЯ `#burn?` (ARCH.101: знак `amount` напрямку не
      #     видає — slash пишеться додатним), плюс сирий `sourceable_type` як її
      #     доказ для зовнішнього аудитора;
      #   · одиниці стоять у ЗАГОЛОВКАХ колонок (CLAUDE §6: із самого імені
      #     колонки одиниця не видна — `amount` = монети, `locked` = бали);
      #   · значення сирі, без округлення (аудит-документ — прецедент ARCH.88:
      #     машинним споживачам віддаємо numeric(24,6) як є).
      # Обсяг пер-гаманцевий (сотні рядків), тож ORDER без батчингу чесний;
      # find_each тут не можна — він ігнорує ORDER і йде по PK повз партиційний
      # індекс wallet_id.
      def generate_ledger_csv_enum(wallet)
        Enumerator.new do |yielder|
          yielder << CSV.generate_line([ "Wallet Ledger" ])
          yielder << CSV.generate_line([ "Wallet ID", wallet.id ])
          yielder << CSV.generate_line([ "Address", wallet.crypto_public_address ])
          yielder << CSV.generate_line([ "Generated At", Time.current.iso8601 ])
          yielder << CSV.generate_line([])
          yielder << CSV.generate_line([ "Created At", "Direction", "Token", "Amount (coins)",
                                         "Locked (growth points)", "Status", "Network",
                                         "Tx Hash", "To Address", "Source Type" ])
          wallet.blockchain_transactions.order(created_at: :desc).each do |tx|
            yielder << CSV.generate_line([
              tx.created_at.iso8601, tx.burn? ? "burn" : "mint", tx.token_type,
              tx.amount, tx.locked_points, tx.status, tx.blockchain_network,
              tx.tx_hash, tx.to_address, tx.sourceable_type
            ])
          end
        end
      end
    end
  end
end
