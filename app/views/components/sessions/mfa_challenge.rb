# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Sessions
  # [S6.21] Другий фактор входу: TOTP-код або одноразовий recovery-код.
  # Стиль-близнюк `Sessions::New` (та сама auth-сторінка, той самий шар довіри);
  # ДВА окремі поля свідомо — одне поле на обидва формати змушувало б сервер
  # угадувати, що саме ввели, а recovery легально виглядає як «зіпсутий» TOTP.
  class MfaChallenge < ApplicationComponent
    # @param flash_alert [String, nil] помилка ПОТОЧНОГО сабміту (401/429) —
    #   рендер на місці, як у `Sessions::New`.
    def initialize(flash_alert: nil)
      @flash_alert = flash_alert
    end

    def view_template
      main(class: "min-h-screen bg-gaia-surface-base flex items-center justify-center p-4 font-mono relative overflow-hidden", role: "main") do
        div(class: "w-full max-w-md relative z-10") do
          render_header

          form_with(url: mfa_challenge_path, method: :post, class: "p-8 border border-gaia-border bg-gaia-surface/80 backdrop-blur-xl space-y-8") do |f|
            render_flash_messages

            div(class: "space-y-6") do
              field_container(f, :otp_code, t(".code_label")) do
                f.text_field :otp_code, class: input_classes, placeholder: "000000",
                                        autofocus: true, autocomplete: "one-time-code",
                                        inputmode: "numeric"
              end
            end

            div(class: "pt-4") do
              f.submit t(".submit").upcase, class: submit_classes
            end

            render_recovery_section(f)
          end
        end
      end
    end

    private

    def render_header
      div(class: "text-center mb-10 space-y-2") do
        h1(class: "text-3xl font-extralight text-gaia-text-strong tracking-[0.3em] uppercase") { t(".title") }
        p(class: "text-tiny text-gaia-text-muted uppercase tracking-[0.5em]") { t(".subtitle") }
      end
    end

    # Запасний вихід: одноразовий recovery-код. `details` замість JS-тумблера —
    # нативний елемент, нуль контролерів (драбинка CLAUDE §4).
    def render_recovery_section(form)
      details(class: "pt-4 border-t border-gaia-border") do
        summary(class: "text-tiny text-gaia-text-muted uppercase tracking-widest cursor-pointer " \
                       "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong") do
          t(".use_recovery")
        end
        div(class: "pt-4") do
          field_container(form, :recovery_code, t(".recovery_label")) do
            form.text_field :recovery_code, class: input_classes, autocomplete: "off"
          end
        end
      end
    end

    def field_container(form, attribute, text)
      div(class: "space-y-2") do
        label(for: form.field_id(attribute), class: "text-tiny text-gaia-text-muted uppercase tracking-widest") { text }
        yield
      end
    end

    def input_classes
      "w-full bg-gaia-surface-sunken border border-gaia-border-strong text-gaia-text-strong p-4 font-mono text-sm focus-visible:border-gaia-primary focus-visible:ring-0 outline-none transition-all placeholder:text-gaia-text-subtle"
    end

    def submit_classes
      "w-full py-4 bg-emerald-500/10 border border-gaia-primary text-gaia-primary-strong uppercase text-xs tracking-[0.4em] " \
        "hover:bg-emerald-500 hover:text-gaia-surface focus-visible:outline-none focus-visible:ring-2 " \
        "focus-visible:ring-gaia-primary-strong transition-all cursor-pointer"
    end

    def render_flash_messages
      return if @flash_alert.blank?

      div(class: tokens(
        "p-3 border border-status-danger bg-status-danger text-status-danger-text",
        "text-tiny uppercase tracking-widest text-center"
      ), role: "alert") do
        @flash_alert
      end
    end
  end
end
