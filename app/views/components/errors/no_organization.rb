# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Standalone Phlex page rendered inside AuthLayout when an authenticated user
# has no organization assigned (наприклад, системний бот Oracle Executioner,
# або щойно створений акаунт у процесі onboarding).
#
# Стиль: domain page-component (auth-сторінка), тому використовує raw emerald
# Tailwind токени узгоджено з Sessions::New / Passwords::Forgot
# (див. docs/04_04 §3.5 — виняток для domain page-components).
module Errors
  class NoOrganization < ApplicationComponent
    # @param current_user [User, nil] актор — потрібен ЛИШЕ щоб вирішити, чи є
    #   звідси вихід [UI.6]
    #
    # 🔴 Ця сторінка — не рідкісний кут, а ПЕРШИЙ екран платформеного адміністратора:
    # за seeds обидва super_admin створюються без організації, логін веде на
    # `dashboard#index`, а той першим рядком кличе `acting_organization!`. Тобто до
    # цього фіксу акаунт архітектора після входу впирався в сторінку, де єдина дія —
    # вийти. Для super_admin вихід є: обрати контекст у реєстрі кланів.
    #
    # Дефолт `nil` fail-CLOSED: без актора лінка немає. Для всіх інших ролей його
    # немає й по суті — реєстр за `authorize_super_admin!`, тож кнопка була б
    # запрошенням у 403.
    def initialize(current_user: nil)
      @current_user = current_user
    end

    def view_template
      main(
        class: "min-h-screen flex items-center justify-center p-4 relative overflow-hidden",
        role: "main"
      ) do
        div(
          class: "absolute inset-0 opacity-10 pointer-events-none bg-[radial-gradient(#10b981_1px,transparent_1px)] [background-size:20px_20px]",
          aria_hidden: "true"
        )

        div(class: "w-full max-w-md animate-in zoom-in duration-700 relative z-10") do
          render_header

          div(class: "p-8 border border-emerald-900 bg-black/80 backdrop-blur-xl shadow-[0_0_50px_rgba(16,185,129,0.1)] space-y-8") do
            render_message
            render_choose_organization
            render_logout_link
          end
        end
      end
    end

    private

    def render_header
      div(class: "text-center mb-10 space-y-2") do
        div(class: "inline-block h-12 w-12 border border-status-danger-accent rotate-45 mb-4 relative", aria_hidden: "true") do
          div(class: "absolute inset-1 bg-status-danger-accent animate-pulse")
        end
        h1(class: "text-3xl font-extralight text-white tracking-[0.3em] uppercase") { t(".heading") }
        p(class: "text-tiny text-emerald-700 uppercase tracking-[0.5em]") { t(".subtitle") }
      end
    end

    def render_message
      div(class: "space-y-4 text-compact text-emerald-300/80 leading-relaxed") do
        p do
          plain t(".body_1")
        end
        # Другий абзац роле-залежний, і це не оздоба: «зверніться до адміністратора»
        # адресовано тому, кого забули додати в організацію. Super_admin — сам той
        # адміністратор, і його стан інший: членства не бракує, бракує ОБРАНОГО
        # контексту. Лишити спільний текст означало б поставити кнопку виходу
        # впритул до речення, яке заперечує її існування.
        p(class: "text-tiny text-emerald-700 uppercase tracking-widest") do
          t(super_admin? ? ".body_2_super_admin" : ".body_2")
        end
      end
    end

    def render_choose_organization
      return unless super_admin?

      div(class: "text-center") do
        a(
          href: api_v1_organizations_path,
          class: "inline-block px-6 py-3 border border-emerald-500 text-emerald-400 text-tiny uppercase " \
                 "tracking-[0.3em] hover:bg-emerald-500 hover:text-black transition-colors " \
                 "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500"
        ) { t(".choose_organization") }
      end
    end

    # Диспетчер, а не правило: кличе той самий предикат `User`, який читає
    # `authorize_super_admin!` на реєстрі кланів. Немає актора — немає виходу.
    def super_admin?
      @current_user&.role_super_admin?
    end

    def render_logout_link
      div(class: "pt-4 border-t border-emerald-900/30 text-center") do
        button_to(
          t(".sign_out"),
          api_v1_logout_path,
          method: :delete,
          aria: { label: "Sign out" },
          class: "text-tiny text-emerald-900 uppercase tracking-widest hover:text-emerald-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 transition-colors bg-transparent border-0 cursor-pointer"
        )
      end
    end
  end
end
