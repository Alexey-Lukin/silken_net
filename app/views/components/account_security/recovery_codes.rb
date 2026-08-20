# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module AccountSecurity
  # [S6.21] Одноразовий показ recovery-набору після активації MFA чи ротації.
  #
  # Компонент бачить набір РІВНО раз (session-маркер знімається контролером до
  # рендеру), тож увесь його зміст — «збережи ЗАРАЗ»: повний список + гучне
  # попередження, що повторного показу не буде, лише ротація нового набору.
  #
  # ⚠️ Токени, не сира палітра: компонент народжений після присуду 04_04 §3.5,
  # тож не успадковує борг немігрованих сусідів (mfa_setup писався до нього).
  class RecoveryCodes < ApplicationComponent
    # @param codes [Array<String>] повний recovery-набір (з БД, під автентифікацією)
    def initialize(codes:)
      @codes = codes
    end

    def view_template
      div(class: "max-w-2xl mx-auto space-y-8") do
        render_header
        div(class: "p-6 border border-gaia-border bg-gaia-surface space-y-6") do
          render_warning
          render_codes
          render_done_link
        end
      end
    end

    private

    def render_header
      div(class: "space-y-2") do
        h2(class: "text-xl font-light text-gaia-text-strong uppercase tracking-widest") { t(".heading") }
        p(class: "text-tiny text-gaia-text-muted") { t(".subtitle") }
      end
    end

    # Попередження — сигнальний текст: насичений -accent (пастельний status-*
    # є фоном бейджа й на поверхні нечитабельний — 04_04 §3.2).
    def render_warning
      div(class: "p-3 border border-status-warning-accent space-y-1", role: "alert") do
        p(class: "text-tiny text-status-warning-accent uppercase tracking-widest") { t(".one_time_warning") }
        p(class: "text-mini text-gaia-text-muted") { t(".store_hint") }
      end
    end

    def render_codes
      ul(class: "grid grid-cols-2 gap-3") do
        @codes.each do |code|
          li(class: "p-3 border border-gaia-border bg-gaia-surface-sunken " \
                    "font-mono text-sm text-gaia-text-strong tracking-[0.2em] text-center") { code }
        end
      end
    end

    def render_done_link
      div(class: "pt-4 border-t border-gaia-border text-center") do
        a(href: account_security_path,
          class: "inline-block px-6 py-2 border border-gaia-primary-strong text-tiny " \
                 "text-gaia-primary-strong uppercase tracking-widest " \
                 "hover:bg-gaia-primary hover:text-gaia-primary-text " \
                 "focus-visible:outline-none focus-visible:ring-2 " \
                 "focus-visible:ring-gaia-primary-strong transition-all") { t(".done") }
      end
    end
  end
end
