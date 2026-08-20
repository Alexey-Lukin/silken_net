# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Organizations
  class Show < ApplicationComponent
    # @param acting_organization [Organization, nil] контекст запиту [UI.6]
    #
    # Профіль клану — четверта посадка того самого класу «право без переходу»:
    # саме тут super_admin вирішує, чи входити в цей контекст, і саме звідси
    # здатність зникала (з рядка реєстру вели ДВІ дії, а на сторінці лишалась одна).
    def initialize(organization:, clusters:, performance:, acting_organization: nil)
      @organization = organization
      @clusters = clusters
      @performance = performance
      @acting_organization = acting_organization
    end

    def view_template
      div(class: "space-y-10") do
        render_header
        render_performance_hero

        div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
          # Основний список секторів
          div(class: "xl:col-span-2 space-y-6") do
            render_clusters_registry
          end

          # Бічна панель ідентичності
          div(class: "space-y-6") do
            render_identity_vault
            render_recent_activity_placeholder
          end
        end
      end
    end

    private

    # Дзеркало клітинки реєстру: маркер, коли вже тут, кнопка — коли ні.
    # [UI.11] `turbo: "false"` знято разом із причиною — деталь у дзеркалі
    # (`organizations/index.rb`).
    def render_context_action
      if @acting_organization&.id == @organization.id
        span(
          aria_current: "true",
          class: "text-mini uppercase tracking-widest text-gaia-primary-strong border border-gaia-border-strong px-3 py-1"
        ) { t(".current_context") }
        return
      end

      button_to(
        t(".switch"),
        switch_organization_path(@organization),
        method: :post,
        aria: { label: t(".switch_aria", name: @organization.name) },
        class: "text-mini uppercase tracking-widest border border-gaia-border-strong text-gaia-text " \
               "px-3 py-1 hover:bg-gaia-primary hover:text-gaia-primary-text transition-colors cursor-pointer " \
               "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong"
      )
    end

    def render_header
      div(class: "flex flex-col md:flex-row justify-between items-start md:items-center p-8 border border-gaia-border bg-gaia-surface shadow-2xl relative overflow-hidden") do
        # Декоративний фон для ідентифікації
        div(class: "absolute top-0 right-0 p-4 text-[80px] font-bold text-emerald-900/5 select-none", aria_hidden: "true") { t(".hero_decoration") }

        div do
          h2(class: "text-4xl font-extralight tracking-tighter text-gaia-text") { @organization.name }
          p(class: "text-tiny font-mono text-gaia-text-subtle uppercase mt-2 tracking-[0.3em]") do
            t(".member_since", date: @organization.created_at.strftime("%d.%m.%Y"))
          end
        end

        # 🔴 [ARCH.84] Блок «Operational Status: FULLY_SYNCED» + зелена лампа
        # ЗНЯТО 2026-08-14: обидва були безумовними літералами, а колонки стану
        # синхронізації в `Organization` не існує ВЗАГАЛІ — тобто свіжостворена
        # організація з нулем кластерів урочисто заявляла «повністю синхронізовано»,
        # і лампа світилась зеленим над порожнечею.
        #
        # ⚠️ Чому ЗНЯТО, а не переведено в «не виміряно»: третій стан має сенс
        # там, де вимір ПЕРЕДБАЧЕНИЙ і не відбувся (прецедент — `latest_stress_index`,
        # `probability_score`). Тут не існує самого поняття: показати «не виміряно»
        # означало б стверджувати, що така метрика має бути. Той самий вибір, що
        # для стрес-дуги: без виміру елемент не малюється взагалі.
        #
        # 🧭 Чи потрібен організації операційний статус і З ЧОГО його деривувати
        # (свіжість шлюзів? тиша дерев? покриття телеметрії?) — відкрите ⚖️ у
        # `00_07` ARCH.84: це продуктове питання, і вигадувати відповідь у в'ю
        # означало б завести четвертий дім чужого рішення.
        div(class: "mt-6 md:mt-0 flex items-center gap-4") do
          render_context_action
        end
      end
    end

    def render_performance_hero
      div(class: "grid grid-cols-1 md:grid-cols-3 gap-6") do
        render Views::Shared::UI::StatCard.new(label: t(".performance.biological_assets"), value: @performance[:total_trees], sub: t(".performance.biological_assets_sub"))
        render Views::Shared::UI::StatCard.new(label: t(".performance.carbon_yield"), value: @performance[:carbon_minted], sub: t(".performance.carbon_yield_sub"))
        render Views::Shared::UI::StatCard.new(label: t(".performance.capital_injected"), value: @organization.total_contracted, sub: t(".performance.capital_injected_sub"))
      end
    end

    def render_clusters_registry
      div(class: "space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".clusters.title") }

        div(class: "border border-gaia-border bg-gaia-surface overflow-x-auto w-full") do
          table(role: "table", class: "w-full text-left font-mono text-compact") do
            thead(class: "bg-gaia-surface-sunken text-gaia-text-subtle uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { t(".clusters.sector_name") }
                th(scope: "col", class: "p-4") { t(".clusters.vitality") }
                th(scope: "col", class: "p-4") { t(".clusters.population") }
                th(scope: "col", class: "p-4 text-right") { t(".clusters.matrix") }
              end
            end
            tbody(class: "divide-y divide-gaia-border") do
              @clusters.each do |cluster|
                tr(class: "hover:bg-gaia-surface-sunken transition-colors group") do
                  td(class: "p-4 text-gaia-text-strong") { cluster.name }
                  td(class: "p-4") do
                    div(class: "flex items-center gap-2") do
                      # [ARCH.84] Невиміряний кластер НЕ отримує смуги взагалі. Тире сюди
                      # покласти неможливо — це CSS-довжина, — а нульова ширина читалась би
                      # як виміряні 0%, тобто як мертвий ліс. Відсутність смуги = відсутність
                      # твердження про величину; саме твердження несе підпис поруч.
                      if !cluster.health_index.nil?
                        div(class: "w-16 h-1 bg-gaia-surface-sunken rounded-full overflow-hidden") do
                          div(class: "h-full bg-gaia-primary", style: "width: #{(cluster.health_index * 100).round}%")
                        end
                      end
                      span(class: tokens("text-tiny",
                                         "text-gaia-primary-strong": !cluster.health_index.nil?,
                                         "text-status-neutral-text": !!cluster.health_index.nil?)) do
                        measured_percent(cluster.health_index)
                      end
                    end
                  end
                  td(class: "p-4 text-gaia-text-subtle") { t(".clusters.soldiers_count", count: cluster.total_active_trees) }
                  td(class: "p-4 text-right") do
                    a(
                      href: cluster_path(cluster),
                      class: "text-gaia-primary-strong hover:text-gaia-text-strong transition-all uppercase text-mini focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong",
                      aria_label: t(".clusters.open_aria", name: cluster.name)
                    ) { t(".clusters.open_matrix") }
                  end
                end
              end
            end
          end
        end
      end
    end

    def render_identity_vault
      div(class: "p-6 border border-gaia-border bg-gaia-surface space-y-6") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".identity_vault.title") }

        div do
          p(class: "text-mini text-gaia-text-muted uppercase mb-2") { t(".identity_vault.public_address") }
          render Views::Shared::Web3::Address.new(address: @organization.crypto_public_address)
        end

        div(class: "pt-4 border-t border-gaia-border") do
          p(class: "text-mini text-gaia-text-muted uppercase mb-2") { t(".identity_vault.billing_contact") }
          p(class: "text-compact text-gaia-text-subtle") { @organization.billing_email || t(".identity_vault.not_available") }
        end
      end
    end

    def render_recent_activity_placeholder
      div(class: "p-6 border border-gaia-border bg-gaia-surface-sunken") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-4") { t(".activity.title") }
        div(class: "space-y-3") do
          [
            t(".activity.contract_renewal"),
            t(".activity.asset_expansion"),
            t(".activity.carbon_audit")
          ].each do |event|
            div(class: "flex justify-between items-center") do
              span(class: "text-tiny text-gaia-text-muted uppercase font-mono") { event }
              span(class: "text-mini text-gaia-text-subtle") { t(".activity.pending") }
            end
          end
        end
      end
    end
  end
end
