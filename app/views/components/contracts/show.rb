# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Contracts
  class Show < ApplicationComponent
    def initialize(contract:, history:)
      @contract = contract
      @history = history
    end

    def view_template
      div(class: "space-y-8") do
        render_hero_section

        div(class: "grid grid-cols-1 lg:grid-cols-3 gap-8") do
          div(class: "lg:col-span-2 space-y-8") do
            render_emission_ledger
          end
          div(class: "space-y-8") do
            render_backing_asset_panel
            render_legal_vault
          end
        end
      end
    end

    private

    def render_hero_section
      div(class: "p-10 border border-emerald-900 bg-zinc-950 flex flex-col md:flex-row justify-between items-center relative overflow-hidden") do
         div(class: "absolute top-0 right-0 p-4 text-[100px] font-bold text-emerald-900/5 select-none", aria_hidden: "true") { t(".decoration") }

         div do
           p(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700 mb-2") { t(".identity") }
           h2(class: "text-5xl font-extralight text-white tracking-tighter") { t(".title", id: @contract.id, sector: @contract.cluster&.name&.upcase) }
           p(class: "mt-2 text-xs font-mono text-gaia-text-muted") { t(".organization", name: @contract.organization&.name) }
           # Сире значення enum'а, інтерпольоване в ПЕРЕКЛАДЕНЕ речення, — найгірший
           # підвид класу (`04_04 §12.14`): фраза виглядає локалізованою, тож при
           # вичитці її пропускають. Мітку резолвить єдиний дім деривації.
           p(class: "mt-1 text-xs font-mono text-gaia-text-muted") { t(".status", value: Views::Shared::UI::StatusBadge.label(@contract.status).upcase) }
           p(class: "mt-1 text-xs font-mono text-gaia-text-muted") { t(".period", start: @contract.start_date&.strftime("%d.%m.%Y"), end: @contract.end_date&.strftime("%d.%m.%Y")) }
           p(class: "mt-1 text-xs font-mono text-gaia-text-muted") { t(".total_funding", amount: @contract.total_funding) }
         end

         div(class: "mt-8 md:mt-0 text-center md:text-right") do
           p(class: "text-tiny text-gray-600 uppercase mb-1") { t(".current_yield") }
           span(class: "text-6xl font-light text-emerald-400") { @contract.emitted_tokens.to_f.round(2) }
           span(class: "text-xl text-emerald-600 font-mono ml-2") { t(".yield_unit") }
         end
      end
    end

    def render_backing_asset_panel
      cluster = @contract.cluster
      return unless cluster

      # [ARCH.84] Тут доти стояв `health = cluster.health_index || 0`, і на невиміряному
      # кластері панель ЗАСТАВИ друкувала «0%» червоним пульсуючим — тобто вигадане
      # число під виглядом виміру, ще й у найгучнішій формі.
      #
      # 🔴 Але й тиха нейтральна комірка була б дефектом, лише протилежним: арбітражний
      # шар на ту саму порожнечу піднімає `flag_data_blackout!` → Field Audit (`05_05 §6`,
      # «absence-of-data → freeze, NEVER slash»), а `BlockchainBurningService` дає
      # `:frozen`. **UI не сміє бути ТИХІШИМ за шар, який він відображає.** Тому станів
      # три, і третій — власний: не тривога (її підстава — вимір) і не норма.
      measured = !cluster.health_index.nil?

      div(class: "p-6 border border-emerald-900 bg-black") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-6") { t(".backing.title") }
        div(class: "space-y-4") do
          metric_row(t(".backing.vitality"),
                     measured_percent(cluster.health_index),
                     alert: measured && cluster.health_index < 0.7,
                     unmeasured: !measured)
          metric_row(t(".backing.active_soldiers"), cluster.total_active_trees)
          threats = cluster.active_threats? # один читок: предикат б'є в БД (див. `Clusters::Item`)
          metric_row(t(".backing.threat_status"), threats ? t(".backing.danger") : t(".backing.nominal"), alert: threats)
        end
      end
    end

    # [ARCH.84] Три стани, не два: `alert` = виміряно й погано · `unmeasured` = виміру
    # не було · решта = виміряно й нормально. Пульсацію свідомо НЕ віддано третьому —
    # вона стверджує деградацію, а її підстава тут відсутня.
    def metric_row(label, value, alert: false, unmeasured: false)
      div(class: "flex justify-between border-b border-emerald-900/30 pb-2") do
        span(class: "text-tiny text-gray-600 uppercase") { label }
        span(class: tokens("font-mono text-sm",
                           "text-red-500 animate-pulse": alert,
                           "text-status-warning-text": unmeasured,
                           "text-emerald-100": !alert && !unmeasured)) { value }
      end
    end

    def render_emission_ledger
      div(class: "space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700") { t(".ledger.title") }
        div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
           table(role: "table", class: "w-full text-left font-mono text-tiny") do
             thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
               tr do
                 th(scope: "col", class: "p-4") { t(".ledger.tx_hash") }
                 th(scope: "col", class: "p-4") { t(".ledger.amount") }
                 th(scope: "col", class: "p-4 text-right") { t(".ledger.timestamp") }
               end
             end
             tbody(class: "divide-y divide-emerald-900/30") do
                if @history.any?
                  @history.each do |tx|
                    tr(class: "hover:bg-emerald-950/10 transition-colors") do
                      td(class: "p-4 text-emerald-600") { tx.tx_hash.present? ? "#{tx.tx_hash.first(12)}…" : t(".ledger.pending_block") }
                      # 🔴 [ARCH.101] Знак «плюс» був ЗАШИТИЙ у сам рядок локалі, тож слеш
                      # САМЕ ЦЬОГО контракту (`create_slash_intent!` ставить
                      # `sourceable: @naas_contract`) друкувався в його ж «Emission History»
                      # як надходження — на сторінці, яку читає інвестор. Напрямок
                      # деривуємо через `#burn?`; колір іде ПАРОЮ зі знаком, бо самого
                      # мінуса в моноширинному рядку майже не видно.
                      # ⚠️ Плейсхолдер локалі тут НЕ цитуємо дослівно: `phlex_bigdecimal_render_spec`
                      # сканує однорядкові `{…}`-блоки і виключає лише `#{…}`, тож
                      # процентна форма в КОМЕНТАРІ червонить гейт як «голий decimal».
                      td(class: tokens("p-4", "text-white": !tx.burn?, "text-status-danger-text": tx.burn?)) do
                        t(tx.burn? ? ".ledger.amount_value_burn" : ".ledger.amount_value", amount: tx.amount)
                      end
                      td(class: "p-4 text-gray-500 text-right") { tx.created_at.strftime("%H:%M // %d.%m.%y") }
                    end
                  end
                else
                  tr do
                    td(colspan: 3, class: "p-10 text-center text-gray-700 italic") { t(".ledger.empty") }
                  end
                end
             end
           end
        end
      end
    end

    def render_legal_vault
      div(class: "p-6 border border-emerald-900 bg-emerald-950/10") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-4") { t(".legal.title") }
        p(class: "text-tiny text-gray-500 font-mono break-all leading-relaxed mb-4") do
          t(".legal.verified")
        end
        if @contract.cancellation_terms.present?
          div(class: "space-y-2 pt-3 border-t border-emerald-900/30") do
            h4(class: "text-mini uppercase tracking-widest text-emerald-800 mb-2") { t(".legal.cancellation_title") }
            # [ARCH.84] «0%» комісії за дострокове розірвання — ЗАКОННА умова
            # договору, тож підстановка робила «умови не задано» невідрізнимим
            # від «розірвання безкоштовне», і саме в панелі LEGAL VAULT. Чесний
            # сусід стоїть двома рядками нижче (`min_days_before_exit || "—"`).
            # ⚖️ Грошовий двійник (`NaasContract#calculate_early_exit_fee` теж
            # робить `|| 0`) НЕ чіпаємо: скільки платформа стягує за незаданої
            # умови — присуд власника, не правка (`00_07` ARCH.84).
            term_row(t(".legal.early_exit_fee"),
                     if @contract.early_exit_fee_percent
                       t(".legal.early_exit_value", value: @contract.early_exit_fee_percent)
                     else
                       "—"
                     end)
            term_row(t(".legal.burn_points"), @contract.burn_accrued_points ? t(".legal.burn_yes") : t(".legal.burn_no"))
            term_row(t(".legal.min_days"), @contract.min_days_before_exit || "—")
          end
        end
      end
    end

    def term_row(label, value)
      div(class: "flex justify-between text-tiny font-mono") do
        span(class: "text-gray-600") { label }
        span(class: "text-emerald-400") { value.to_s }
      end
    end
  end
end
