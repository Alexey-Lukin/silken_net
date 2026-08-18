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
      div(class: "p-8 border border-emerald-900 bg-black shadow-2xl relative overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[60px] font-bold text-emerald-900/5 select-none", aria_hidden: "true") { t(".decoration") }
        div(class: "flex justify-between items-start") do
          div do
            p(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700 mb-2") { t(".transaction_record") }
            h2(class: "text-3xl font-extralight tracking-tighter text-white") { "#{@tx.amount} #{@tx.ticker}" }
            p(class: "text-tiny font-mono text-gray-600 mt-2") { t(".tx_id_line", id: @tx.id, at: @tx.created_at.strftime("%d.%m.%Y %H:%M:%S UTC")) }
          end
          div(class: "flex items-center gap-3") do
            render Views::Shared::UI::StatusBadge.new(status: @tx.status)
            span(class: tokens("px-3 py-1 text-mini font-bold border", token_badge_styles)) { @tx.token_type_label }
          end
        end
      end
    end

    def render_transaction_details
      div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
        table(role: "table", class: "w-full text-left font-mono text-compact") do
          thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
            tr do
              th(scope: "col", class: "p-4") { t(".details.field") }
              th(scope: "col", class: "p-4") { t(".details.value") }
            end
          end
          tbody(class: "divide-y divide-emerald-900/30") do
            detail_row(t(".details.amount"), "#{@tx.amount} #{@tx.ticker}")
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
      tr(class: "hover:bg-emerald-950/10") do
        td(class: "p-4 text-emerald-500") { label }
        td(class: "p-4 text-gray-300") { value.to_s }
      end
    end

    def render_notes_panel
      div(class: "p-6 border border-emerald-900 bg-black") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-4") { t(".notes.title") }
        if @tx.notes.present?
          p(class: "text-compact text-gray-400 font-mono leading-relaxed") { @tx.notes }
        else
          p(class: "text-compact text-gray-700 italic") { t(".notes.empty") }
        end
        if @tx.error_message.present?
          div(class: "mt-4 p-3 border border-red-900 bg-red-950/20") do
            p(class: "text-mini uppercase text-red-500 tracking-widest mb-1") { t(".notes.error_message") }
            p(class: "text-compact text-red-400 font-mono") { @tx.error_message }
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
      div(class: "p-6 border border-emerald-900 bg-black space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") do
          cluster_sourced? ? t(".wallet.cluster_title") : t(".wallet.title")
        end

        if cluster_sourced?
          p(class: "text-compact text-emerald-400 font-mono") { @tx.cluster.name }
        elsif @tx.wallet.present?
          div do
            p(class: "text-mini text-gray-600 uppercase mb-1") { t(".wallet.tree_did") }
            # `&.` is model-validation-dead, not real: Wallet#tree is a
            # required belongs_to (no `optional: true`) and Tree has
            # `has_one :wallet, dependent: :destroy` — a wallet can never
            # outlive its tree, so `.tree` is always present here.
            p(class: "text-compact text-emerald-400 font-mono") { @tx.wallet.tree&.did || t(".wallet.not_available") }
          end
          div(class: "pt-3 border-t border-emerald-900/30") do
            p(class: "text-mini text-gray-600 uppercase mb-1") { t(".wallet.wallet_balance") }
            p(class: "text-lg text-white font-light") do
              # [ARCH.88] Це БАЛАНС ГАМАНЦЯ, тобто бали росту — на відміну від
              # `@tx.amount` вище, який справді в монетах і носить `@tx.ticker`.
              # Дві сусідні величини на одній сторінці, дві різні одиниці.
              plain formatted_points(@tx.wallet.balance).to_s
              span(class: "text-xs text-emerald-600 ml-2") { t(".wallet.unit") }
            end
          end
        else
          p(class: "text-compact text-gray-700 italic") { t(".wallet.no_wallet") }
        end
      end
    end

    def token_badge_styles
      case @tx.token_type
      when "carbon_coin" then "bg-emerald-900/20 text-emerald-400 border-emerald-500/30"
      when "forest_coin" then "bg-token-forest/20 text-token-forest border-token-forest/30"
      when "cusd" then "bg-zinc-900 text-zinc-400 border-zinc-700"
      else "bg-zinc-900 text-zinc-400 border-zinc-700"
      end
    end
  end
end
