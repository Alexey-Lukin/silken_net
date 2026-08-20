# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Standalone Phlex page rendered inside AuthLayout when an authenticated user
# has no organization assigned (наприклад, системний бот Oracle Executioner,
# або щойно створений акаунт у процесі onboarding).
#
# 🔴 Тут доти стояло, що raw emerald — «виняток для domain page-components» за
# `04_04 §3.5`. Дозвіл СКАСОВАНО 2026-08-07 (`04_04 §1`/`§3.5` звужено до
# тем-інваріантного *й оголошеного*), а покликання «узгоджено з Sessions::New»
# застаріло з протилежного боку: той сусід уже мігрований, тож звірятись треба
# було саме з ним. Вимір на цій сторінці (UI.3, 2026-08-15): заголовок
# `text-white` — **1.04:1** у світлій темі, а `text-emerald-900` на кнопці виходу —
# **1.33:1** світла / **2.17:1** темна, тобто ЄДИНА дія першого екрана
# платформеного адміністратора була невидима в ОБОХ темах.
#
# 🔴 Панель була `bg-black/80`, і саме напівпрозорість робила її оманливою:
# «чорне є чорне» читається як тем-інваріантність, але при α=0.8 вона
# композититься з тлом сторінки — фактично `rgb(50,50,50)` у світлій проти
# `rgb(1,1,1)` у темній. Тобто §3.5-виняток «тем-інваріантне за задумом» на
# будь-яку `/NN`-поверхню не поширюється за побудовою.
#
# Форму взято з мігрованого близнюка `Sessions::New` (той самий екран auth-родини),
# а не винайдено: скло лишається (`bg-gaia-surface/80 backdrop-blur-xl`), змінюється
# лише те, що воно тепер знає про тему.
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
        class: "min-h-screen bg-gaia-surface-base flex items-center justify-center p-4 relative overflow-hidden",
        role: "main"
      ) do
        div(
          class: "absolute inset-0 opacity-10 pointer-events-none bg-[radial-gradient(#10b981_1px,transparent_1px)] [background-size:20px_20px]",
          aria_hidden: "true"
        )

        div(class: "w-full max-w-md relative z-10") do
          render_header

          div(class: "p-8 border border-gaia-border bg-gaia-surface/80 backdrop-blur-xl shadow-[0_0_50px_rgba(16,185,129,0.1)] space-y-8") do
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
        h1(class: "text-3xl font-extralight text-gaia-text-strong tracking-[0.3em] uppercase") { t(".heading") }
        p(class: "text-tiny text-gaia-text-muted uppercase tracking-[0.5em]") { t(".subtitle") }
      end
    end

    def render_message
      div(class: "space-y-4 text-compact text-gaia-text-muted leading-relaxed") do
        p do
          plain t(".body_1")
        end
        # Другий абзац роле-залежний, і це не оздоба: «зверніться до адміністратора»
        # адресовано тому, кого забули додати в організацію. Super_admin — сам той
        # адміністратор, і його стан інший: членства не бракує, бракує ОБРАНОГО
        # контексту. Лишити спільний текст означало б поставити кнопку виходу
        # впритул до речення, яке заперечує її існування.
        p(class: "text-tiny text-gaia-text-subtle uppercase tracking-widest") do
          t(super_admin? ? ".body_2_super_admin" : ".body_2")
        end
      end
    end

    def render_choose_organization
      return unless super_admin?

      div(class: "text-center") do
        a(
          href: organizations_path,
          class: "inline-block px-6 py-3 border border-gaia-primary-strong text-gaia-primary-strong text-tiny uppercase " \
                 "tracking-[0.3em] hover:bg-emerald-500 hover:text-gaia-surface transition-colors " \
                 "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong"
        ) { t(".choose_organization") }
      end
    end

    # Диспетчер, а не правило: кличе той самий предикат `User`, який читає
    # `authorize_super_admin!` на реєстрі кланів. Немає актора — немає виходу.
    def super_admin?
      @current_user&.role_super_admin?
    end

    def render_logout_link
      div(class: "pt-4 border-t border-gaia-border text-center") do
        button_to(
          t(".sign_out"),
          logout_path,
          method: :delete,
          aria: { label: "Sign out" },
          class: "text-tiny text-gaia-text-subtle uppercase tracking-widest hover:text-gaia-primary-strong focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong transition-colors bg-transparent border-0 cursor-pointer"
        )
      end
    end
  end
end
