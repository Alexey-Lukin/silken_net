# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Organizations
  class Index < ApplicationComponent
    # @param acting_organization [Organization, nil] організація, в контексті якої
    #   виконується запит — потрібна ЛИШЕ щоб не пропонувати перемкнутись туди,
    #   де вже стоїш [UI.6]
    #
    # ⚠️ Роле-предиката тут свідомо НЕМАЄ, і це не пропуск: гард контролера
    # КЛАСОВИЙ (`before_action :authorize_super_admin!` без `only:`), тобто дія не
    # глибша за сторінку — умова класу UI.6 не виконується. Порівняй з
    # `Alerts::Row`, де гард стоїть `only: :resolve` і тому кнопку треба гейтувати
    # окремо.
    def initialize(organizations:, pagy:, acting_organization: nil)
      @organizations = organizations
      @pagy = pagy
      @acting_organization = acting_organization
    end

    def view_template
      div(class: "space-y-8 animate-in fade-in duration-700") do
        header_section

        div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
          table(role: "table", class: "w-full text-left font-mono text-compact") do
            thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { t(".columns.name") }
                th(scope: "col", class: "p-4") { t(".columns.sectors") }
                th(scope: "col", class: "p-4") { t(".columns.investment") }
                th(scope: "col", class: "p-4") { t(".columns.identity") }
                th(scope: "col", class: "p-4 text-right") { t(".columns.audit") }
                th(scope: "col", class: "p-4 text-right") { t(".columns.context") }
              end
            end
            tbody(class: "divide-y divide-emerald-900/30") do
              @organizations.each { |org| render_org_row(org) }
            end
          end
        end

        render Views::Shared::UI::Pagination.new(
          pagy: @pagy,
          url_helper: ->(page:) { organizations_path(page: page) }
        )
      end
    end

    private

    def render_org_row(org)
      tr(class: "hover:bg-emerald-950/10 transition-colors group") do
        td(class: "p-4 text-emerald-400 font-bold") { org.name }
        td(class: "p-4 text-gray-400") { org.total_clusters }
        td(class: "p-4 text-emerald-100") { t(".investment_value", amount: org.total_contracted) }
        td(class: "p-4 text-tiny text-gray-600 font-mono") do
          render Views::Shared::Web3::Address.new(address: org.crypto_public_address)
        end
        td(class: "p-4 text-right") do
          a(href: organization_path(org), class: "text-emerald-600 hover:text-white transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500", aria_label: t(".view_aria", name: org.name)) { t(".view_profile") }
        end
        td(class: "p-4 text-right") { render_context_cell(org) }
      end
    end

    # Поточний рядок дістає МАРКЕР, а не дизейблену кнопку. Це не те саме, що
    # присуд «ховати, а не дизейблити» ([`04_04 §6.4`]): там ішлося про дію,
    # недоступну за РОЛЛЮ, і ховали саме тому, що показане меню розкриває мапу
    # можливостей платформи. Тут дія недоступна не за правом, а тому що вже
    # виконана, і порожня клітинка лишила б питання «чому тут нічого». Ідіома в
    # дереві вже є — `aria-current` на активному пункті сайдбара.
    def render_context_cell(org)
      if @acting_organization&.id == org.id
        span(
          aria_current: "true",
          class: "text-mini uppercase tracking-widest text-emerald-500 border border-emerald-800 px-3 py-1"
        ) { t(".current_context") }
        return
      end

      # `turbo: "false"` обов'язковий: сайдбар несе `data-turbo-permanent`
      # (`dashboard_layout.rb`), тож при Turbo-візиті він переживає навігацію разом
      # зі своїм org-скоупленим лічильником тривог — і показав би число ПОПЕРЕДНЬОГО
      # тенанта. Той самий патерн, що в `locale_switcher`: сесійний контекст із
      # хрому міняють повним перезавантаженням.
      #
      # ⚠️ Атрибут іде через `form:`, а не в `html_options`, і це не стиль: `button_to`
      # кладе решту опцій на `<button>`, тоді як прецедент (`locale_switcher`) ставить
      # його на `<form>`. Сьогодні працюють обидва (Turbo 8 перевіряє ще й submitter),
      # але «той самий патерн» має бути тим самим НОСІЄМ, інакше збіг випадковий.
      button_to(
        t(".switch"),
        switch_organization_path(org),
        method: :post,
        form: { data: { turbo: "false" } },
        aria: { label: t(".switch_aria", name: org.name) },
        class: "text-mini uppercase tracking-widest border border-emerald-700 text-emerald-400 " \
               "px-3 py-1 hover:bg-emerald-600 hover:text-black transition-colors cursor-pointer " \
               "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500"
      )
    end

    def header_section
      div(class: "flex justify-between items-end") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { t(".title") }
          p(class: "text-xs text-gray-600 mt-1") { t(".subtitle") }
        end
      end
    end
  end
end
