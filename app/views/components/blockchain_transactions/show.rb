# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module BlockchainTransactions
  class Show < ApplicationComponent
    def initialize(transaction:)
      @tx = transaction
    end

    def view_template
      # [UI.4] Підписки тут НЕМА свідомо. Вона стояла на голий `wallet`-стрім, у який
      # після зняття надлишкового `broadcast_tx_update` не пише ЖОДЕН продюсер; а сама
      # сторінка не рендерить ані `blockchain_transaction_#{id}`, ані `wallet_balance_#{id}`,
      # тож цілитись у неї теж не було чим. Живий оновлювач рядка транзакції —
      # `BlockchainTransaction#broadcast_status_change` → `[wallet, :transactions]`, і його
      # слухає `Wallets::Show`. Щоб оживити ЦЮ сторінку, треба спершу дати їй ціль
      # (`<tr>`-рядок сюди не вставиш — тут не таблиця) → рішення в `00_07` UI.4.

      div(class: "space-y-8") do
        render_header
        div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
          div(class: "xl:col-span-2 space-y-8") do
            render_transaction_details
            render_notes_panel
          end
          div(class: "space-y-8") do
            render_wallet_info
            # Lazy-load: On-Chain Verification підвантажується окремим запитом
            turbo_frame_tag "tx_onchain_frame_#{@tx.id}",
                            src: on_chain_blockchain_transaction_path(@tx),
                            loading: :lazy do
              render Views::Shared::UI::Skeleton.new(variant: :card)
            end
          end
        end
      end
    end

    private

    def render_header
      div(class: "p-8 border border-gaia-border bg-gaia-surface shadow-2xl relative overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[60px] font-bold text-emerald-900/5 select-none", aria_hidden: "true") { t(".decoration") }
        div(class: "flex justify-between items-start") do
          div do
            p(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted mb-2") { t(".transaction_record") }
            # [ARCH.101 ⚖️ 08-20] Знак деривується; колір напрямку приїхав разом із
            # міграцією панелі (дзеркало рядка списку — той самий `#burn?`).
            h2(class: tokens("text-3xl font-extralight tracking-tighter",
                             @tx.burn? ? "text-status-danger-accent" : "text-gaia-text-strong")) { "#{@tx.signed_amount} #{@tx.ticker}" }
            p(class: "text-tiny font-mono text-gaia-text-muted mt-2") { t(".tx_id_line", id: @tx.id, at: @tx.created_at.strftime("%d.%m.%Y %H:%M:%S UTC")) }
          end
          div(class: "flex items-center gap-3") do
            render Views::Shared::UI::StatusBadge.new(status: @tx.status)
            span(class: tokens("px-3 py-1 text-mini font-bold border", token_badge_styles)) { @tx.token_type_label }
          end
        end
      end
    end

    def render_transaction_details
      div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full") do
        table(role: "table", class: "w-full text-left font-mono text-compact") do
          thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-mini tracking-widest") do
            tr do
              th(scope: "col", class: "p-4") { t(".details.field") }
              th(scope: "col", class: "p-4") { t(".details.value") }
            end
          end
          tbody(class: "divide-y divide-gaia-border") do
            detail_row(t(".details.amount"), "#{@tx.signed_amount} #{@tx.ticker}")
            detail_row(t(".details.token_type"), @tx.token_type_label)
            detail_row(t(".details.status"), Views::Shared::UI::StatusBadge.label(@tx.status))
            detail_row(t(".details.blockchain_network"), @tx.blockchain_network&.upcase || "—")
            detail_row(t(".details.locked_points"), @tx.locked_points || "—")
            detail_row(t(".details.to_address"), @tx.to_address)
            detail_row(t(".details.gas_price"), @tx.gas_price ? "#{@tx.gas_price} wei" : "—")
            detail_row(t(".details.gas_used"), @tx.gas_used || "—")
            detail_row(t(".details.block_number"), @tx.block_number || "—")
            detail_row(t(".details.nonce"), @tx.nonce || "—")
            detail_row(t(".details.sent_at"), @tx.sent_at&.strftime("%d.%m.%Y %H:%M:%S") || "—")
            detail_row(t(".details.confirmed_at"), @tx.confirmed_at&.strftime("%d.%m.%Y %H:%M:%S") || "—")
            detail_row(t(".details.created"), @tx.created_at.strftime("%d.%m.%Y %H:%M:%S"))
            detail_row(t(".details.updated"), @tx.updated_at.strftime("%d.%m.%Y %H:%M:%S"))
          end
        end
      end
    end

    def detail_row(label, value)
      # Роль-корекція поверх codemod-мапи: мітка ТИХІША за значення (форма
      # `meta_row` у maintenance/show) — мапа віддала б навпаки.
      tr(class: "hover:bg-gaia-surface-sunken") do
        td(class: "p-4 text-gaia-text-muted") { label }
        td(class: "p-4 text-gaia-text") { value.to_s }
      end
    end

    def render_notes_panel
      div(class: "p-6 border border-gaia-border bg-gaia-surface") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-4") { t(".notes.title") }
        if @tx.notes.present?
          p(class: "text-compact text-gaia-text-subtle font-mono leading-relaxed") { @tx.notes }
        else
          p(class: "text-compact text-gaia-text italic") { t(".notes.empty") }
        end
        if @tx.error_message.present?
          # Пастельна danger-пара за роллю (`04_04 §3.2`: панель = пастель + `-text`);
          # рамка — `-accent`, бо пастельна рамка на світлій поверхні невидима (1.1:1).
          div(class: "mt-4 p-3 border border-status-danger-accent/50 bg-status-danger") do
            p(class: "text-mini uppercase text-status-danger-text tracking-widest mb-1") { t(".notes.error_message") }
            p(class: "text-compact text-status-danger-text font-mono") { @tx.error_message }
          end
        end
      end
    end

    # 🔴 [ARCH.101] Секція називає ДЖЕРЕЛО грошей, і джерел два — гаманцеве дерево
    # АБО кластер. Доти вона знала лише перше: cluster-sourced рух (Celo-винагорода
    # кластеру · слеш «останнього дерева») діставав «Гаманець не прив'язано» і не
    # називав джерела ВЗАГАЛІ — тобто аудитор, що клікнув «Деталі» з рядка, де
    # стояло імʼя кластера, потрапляв на сторінку, яка мовчить про походження
    # найматеріальніших рухів платформи. Заразом розходились дві репрезентації
    # ОДНОГО ендпоінта: блупринт віддає `cluster_name` в обох в'ю, а HTML — ні.
    # ⚠️ Заголовок перемикається РАЗОМ із гілкою: «Прив'язаний гаманець» над іменем
    # кластера був би тим самим «одна мітка, два значення», лише на рівень вище.
    # Той самий предикат читають ОБИДВА боки секції — заголовок і тіло. Дві копії
    # умови розійшлися б тихо: заголовок сказав би «гаманець», а під ним стояв би
    # кластер, і жоден гейт цього не бачить.
    def cluster_sourced? = @tx.wallet.blank? && @tx.cluster.present?

    def render_wallet_info
      div(class: "p-6 border border-gaia-border bg-gaia-surface space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") do
          cluster_sourced? ? t(".wallet.cluster_title") : t(".wallet.title")
        end

        if cluster_sourced?
          p(class: "text-compact text-gaia-text font-mono") { @tx.cluster.name }
        elsif @tx.wallet.present?
          div do
            p(class: "text-mini text-gaia-text-muted uppercase mb-1") { t(".wallet.tree_did") }
            # `&.` is model-validation-dead, not real: Wallet#tree is a
            # required belongs_to (no `optional: true`) and Tree has
            # `has_one :wallet, dependent: :destroy` — a wallet can never
            # outlive its tree, so `.tree` is always present here.
            p(class: "text-compact text-gaia-text font-mono") { @tx.wallet.tree&.did || t(".wallet.not_available") }
          end
          div(class: "pt-3 border-t border-gaia-border") do
            p(class: "text-mini text-gaia-text-muted uppercase mb-1") { t(".wallet.wallet_balance") }
            p(class: "text-lg text-gaia-text-strong font-light") do
              # [ARCH.88] Це БАЛАНС ГАМАНЦЯ, тобто бали росту — на відміну від
              # `@tx.amount` вище, який справді в монетах і носить `@tx.ticker`.
              # Дві сусідні величини на одній сторінці, дві різні одиниці.
              plain formatted_points(@tx.wallet.balance).to_s
              span(class: "text-xs text-gaia-primary-strong ml-2") { t(".wallet.unit") }
            end
          end
        else
          p(class: "text-compact text-gaia-text italic") { t(".wallet.no_wallet") }
        end
      end
    end

    def token_badge_styles
      case @tx.token_type
      # [UI.1] Монетні токени — ролі ФОН/РАМКА, текст нейтральний `gaia-text`
      # для ОБОХ: парного `-text` жоден не має, і обидва провалюють AA у
      # текст-ролі на власній `/20`-підкладці. Правило + числа — дім
      # `Wallets::TransactionRow#tx_type_styles`.
      when "carbon_coin" then "bg-token-carbon/20 text-gaia-text border-token-carbon/30"
      when "forest_coin" then "bg-token-forest/20 text-gaia-text border-token-forest/30"
      # `cusd` СВІДОМО падає в else (зовнішній Celo-долар без власного токена
      # дизайн-системи) — окрема гілка робила б else недосяжним.
      else "bg-gaia-surface text-gaia-text-subtle border-gaia-border-strong"
      end
    end
  end
end
