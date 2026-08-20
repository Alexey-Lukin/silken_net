# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Contracts
  class Show < ApplicationComponent
    # [ARCH.103] `cluster_emission:` — kwarg БЕЗ дефолту: величина належить КЛАСТЕРУ,
    # тож компонент не сміє добувати її сам (Phlex не ходить у БД), а забута проводка
    # мусить падати гучно, а не малювати нуль.
    def initialize(contract:, history:, cluster_emission:)
      @contract = contract
      @history = history
      @cluster_emission = cluster_emission
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
      div(class: "p-10 border border-gaia-border bg-gaia-surface flex flex-col md:flex-row justify-between items-center relative overflow-hidden") do
         div(class: "absolute top-0 right-0 p-4 text-[100px] font-bold text-emerald-900/5 select-none", aria_hidden: "true") { t(".decoration") }

         div do
           p(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted mb-2") { t(".identity") }
           h2(class: "text-5xl font-extralight text-gaia-text-strong tracking-tighter") { t(".title", id: @contract.id, sector: @contract.cluster&.name&.upcase) }
           p(class: "mt-2 text-xs font-mono text-gaia-text-muted") { t(".organization", name: @contract.organization&.name) }
           # Сире значення enum'а, інтерпольоване в ПЕРЕКЛАДЕНЕ речення, — найгірший
           # підвид класу (`04_04 §12.14`): фраза виглядає локалізованою, тож при
           # вичитці її пропускають. Мітку резолвить єдиний дім деривації.
           p(class: "mt-1 text-xs font-mono text-gaia-text-muted") { t(".status", value: Views::Shared::UI::StatusBadge.label(@contract.status).upcase) }
           p(class: "mt-1 text-xs font-mono text-gaia-text-muted") { t(".period", start: @contract.start_date&.strftime("%d.%m.%Y"), end: @contract.end_date&.strftime("%d.%m.%Y")) }
           p(class: "mt-1 text-xs font-mono text-gaia-text-muted") { t(".total_funding", amount: @contract.total_funding) }
         end

         div(class: "mt-8 md:mt-0 text-center md:text-right") do
           p(class: "text-tiny text-gaia-text-muted uppercase mb-1") { t(".cluster_emission") }
           # ✅ [ARCH.103] ⚖️ Присуд founder: контрактну семантику знято на користь
           # КЛАСТЕРНОЇ. Доти тут стояло застереження «підставити кластерну суму
           # означало б замінити фабрикацію підміною — інша множина під тим самим
           # підписом», і воно було правильним рівно доти, доки підпис лишався старим:
           # присуд міняє ОБИДВА боки разом, тож мітка називає кластер явно.
           # 🔴 Гілки «не виміряно» тут НЕМА свідомо: `naas_contracts.cluster_id` це
           # `NOT NULL` ⊕ `belongs_to :cluster` без `optional:`, тож субʼєкт гарантований,
           # а нуль є ВИМІРОМ. Гілка під недосяжний стан обіцяла б читачеві, що такий
           # контракт буває.
           span(class: "text-6xl font-light text-gaia-text-strong") { formatted_amount(@cluster_emission) }
           span(class: "text-xl text-gaia-primary-strong font-mono ml-2") { t(".yield_unit") }
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

      div(class: "p-6 border border-gaia-border bg-gaia-surface") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-6") { t(".backing.title") }
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
      div(class: "flex justify-between border-b border-gaia-border pb-2") do
        span(class: "text-tiny text-gaia-text-muted uppercase") { label }
        span(class: tokens("font-mono text-sm",
                           "text-status-danger-accent": alert,
                           "text-status-warning-accent": unmeasured,
                           "text-gaia-text-strong": !alert && !unmeasured)) { value }
      end
    end

    def render_emission_ledger
      div(class: "space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".ledger.title") }
        div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full") do
           table(role: "table", class: "w-full text-left font-mono text-tiny") do
             thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-mini tracking-widest") do
               tr do
                 th(scope: "col", class: "p-4") { t(".ledger.tx_hash") }
                 th(scope: "col", class: "p-4") { t(".ledger.amount") }
                 th(scope: "col", class: "p-4 text-right") { t(".ledger.timestamp") }
               end
             end
             tbody(class: "divide-y divide-gaia-border") do
                if @history.any?
                  @history.each do |tx|
                    tr(class: "hover:bg-gaia-surface-sunken transition-colors") do
                      td(class: "p-4 text-gaia-primary-strong") { tx.tx_hash.present? ? "#{tx.tx_hash.first(12)}…" : t(".ledger.pending_block") }
                      # 🔴 [ARCH.101] Знак «плюс» був ЗАШИТИЙ у сам рядок локалі, тож слеш
                      # САМЕ ЦЬОГО контракту (`create_slash_intent!` ставить
                      # `sourceable: @naas_contract`) друкувався в його ж «Emission History»
                      # як надходження — на сторінці, яку читає інвестор. Напрямок
                      # деривуємо через `#burn?`; колір іде ПАРОЮ зі знаком, бо самого
                      # мінуса в моноширинному рядку майже не видно.
                      # ⚠️ Плейсхолдер локалі тут НЕ цитуємо дослівно: `phlex_bigdecimal_render_spec`
                      # сканує однорядкові `{…}`-блоки і виключає лише `#{…}`, тож
                      # процентна форма в КОМЕНТАРІ червонить гейт як «голий decimal».
                      td(class: tokens("p-4", "text-gaia-text-strong": !tx.burn?, "text-status-danger-accent": tx.burn?)) do
                        t(tx.burn? ? ".ledger.amount_value_burn" : ".ledger.amount_value", amount: tx.amount)
                      end
                      td(class: "p-4 text-gaia-text-muted text-right") { tx.created_at.strftime("%H:%M // %d.%m.%y") }
                    end
                  end
                else
                  tr do
                    td(colspan: 3, class: "p-10 text-center text-gaia-text-subtle italic") { t(".ledger.empty") }
                  end
                end
             end
           end
        end
      end
    end

    def render_legal_vault
      div(class: "p-6 border border-gaia-border bg-gaia-surface-sunken") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-4") { t(".legal.title") }
        # [UI.17] Тут безумовно стояло «Verified by Silken Net Oracle. Emission
        # indexed to verified homeostasis.» — заява про ДВІ величини, жодна з
        # яких її не підтримує: `emitted_tokens` була колонкою без писача
        # (ARCH.103, структурно завжди 0.0; нині знята зі схеми), а
        # `health_index` має власну гілку «not measured» за двадцять рядків
        # вище. ⚖️ Присуд founder
        # 2026-08-19: зняти зараз, а формулювання юридичної панелі — окремим
        # residual'ом у §07, бо це єдиний сайт класу, де текст може мати
        # ДОГОВІРНУ вагу, і тоді його відсутність безпечніша за перефразування.
        if @contract.cancellation_terms.present?
          div(class: "space-y-2 pt-3 border-t border-gaia-border") do
            h4(class: "text-mini uppercase tracking-widest text-gaia-text-subtle mb-2") { t(".legal.cancellation_title") }
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
        span(class: "text-gaia-text-muted") { label }
        span(class: "text-gaia-text-strong") { value.to_s }
      end
    end
  end
end
