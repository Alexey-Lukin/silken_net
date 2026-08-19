# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Users
  class Index < ApplicationComponent
    def initialize(users:, pagy: nil)
      @users = users
      @pagy = pagy
    end

    def view_template
      div(class: "space-y-8") do
        header_section

        div(class: "border border-emerald-900 bg-black overflow-x-auto w-full") do
          table(role: "table", class: "w-full text-left font-mono text-compact") do
            thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-mini tracking-widest") do
              tr do
                th(scope: "col", class: "p-4") { t(".table.identity") }
                th(scope: "col", class: "p-4") { t(".table.role_access") }
                th(scope: "col", class: "p-4") { t(".table.neural_link") }
                th(scope: "col", class: "p-4 text-right") { t(".table.audit") }
              end
            end
            tbody(class: "divide-y divide-emerald-900/30") do
              @users.each { |user| render_user_row(user) }
            end
          end
        end

        if @pagy
          render Views::Shared::UI::Pagination.new(
            pagy: @pagy,
            url_helper: ->(page:) { users_path(page: page) }
          )
        end
      end
    end

    private

    def header_section
      div(class: "flex justify-between items-end mb-6") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { t(".heading") }
          p(class: "text-xs text-gray-600 mt-1") { t(".subtitle") }
        end
      end
    end

    def render_user_row(user)
      tr(class: "hover:bg-emerald-950/10 transition-colors group") do
        td(class: "p-4") do
          div(class: "flex items-center gap-3") do
            div(class: "h-8 w-8 rounded-full bg-emerald-900/20 border border-emerald-800 flex items-center justify-center text-emerald-500 font-bold") { user.first_name&.first || user.email_address.first }
            span(class: "text-emerald-100") { "#{user.first_name} #{user.last_name}" }
          end
        end
        td(class: "p-4") do
          span(class: tokens("px-2 py-0.5 rounded-sm text-mini font-bold uppercase", role_color(user.role))) { user.role_label }
        end
        td(class: "p-4 text-gray-600") do
           if user.last_seen_at
             render Views::Shared::UI::RelativeTime.new(
               datetime: user.last_seen_at,
               css_class: "text-gray-600 text-compact font-mono",
               prefix: "#{t('.active_prefix')} "
             )
           else
             plain t(".link_offline")
           end
        end
        td(class: "p-4 text-right") do
          # Аудиторії збігаються точно, тож роле-гейт тут не потрібен: `UserPolicy#index?`
          # і `AuditLogsController#authorize_admin!` обидва питають `admin_or_above?`.
          a(
            href: audit_logs_path(user_id: user.id),
            class: "text-emerald-700 hover:text-white transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong",
            aria_label: t(".table.view_logs_aria", name: "#{user.first_name} #{user.last_name}")
          ) { t(".table.view_logs") }
        end
      end
    end

    # 🔴 [TEST.12] `super_admin` мусить мати ВЛАСНУ гілку: enum має чотири значення,
    # а мапа знала три — тож найпривілейованіша роль падала в той самий `else`, що й
    # пошкоджене значення, тобто візуально не відрізнялась від «невідомо що це».
    # Бурштин, а не червоний: платформенний рівень стоїть НАД org-адміном, і сусідні
    # кольори вже зайняті ієрархією investor→forester→admin.
    #
    # ⚠️ Мапа лишається ПРИВАТНОЮ свідомо. Спільний `StatusBadge::STYLES` не містить
    # жодного ключа ролі (перевірено), тож дротування туди сьогодні поклало б у дефолт
    # УСІ чотири значення — гірше за наявний стан. Перевести родину можна лише разом із
    # мітками ×4 локалі, і це черга [`I18N.1`] (net-new authoring), не цей пункт.
    def role_color(role)
      case role
      when "super_admin" then "bg-amber-900/50 text-amber-200 border border-amber-800"
      when "admin" then "bg-red-900/50 text-red-200 border border-red-800"
      when "forester" then "bg-emerald-900/50 text-emerald-200 border border-emerald-800"
      when "investor" then "bg-blue-900/50 text-blue-200 border border-blue-800"
      else "bg-zinc-800 text-zinc-400"
      end
    end
  end
end
