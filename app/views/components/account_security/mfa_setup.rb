# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module AccountSecurity
  # [S6.21] Екран підключення authenticator-а: QR (offline-SVG, rqrcode) + секрет
  # для ручного введення + форма verify-коду, що і активує MFA.
  #
  # ⚠️ QR — інлайн-SVG з НАШОГО ж `otp_provisioning_uri`, не зовнішній ресурс
  # (CSP-чистий); `raw safe(...)` тут легальний, бо вміст генерує rqrcode із
  # значень, які ми самі щойно створили (секрет — Base32 власного провижну).
  class MfaSetup < ApplicationComponent
    # @param user  [User]        власник setup-флоу (секрет уже спровижнений)
    # @param error [String, nil] помилка ПОТОЧНОГО сабміту verify-коду (422)
    def initialize(user:, error: nil)
      @user = user
      @error = error
    end

    def view_template
      div(class: "max-w-2xl mx-auto space-y-8") do
        render_header
        div(class: "p-6 border border-gaia-border bg-gaia-surface space-y-6") do
          render_qr_block
          render_secret_block
          render_confirm_form
        end
      end
    end

    private

    def render_header
      div(class: "space-y-2") do
        h2(class: "text-xl font-light text-gaia-text-strong uppercase tracking-widest") { t(".title") }
        p(class: "text-tiny text-gaia-text-muted") { t(".scan_hint") }
      end
    end

    # [UI.1] `bg-white` тем-інваріантний ЗА ЗАДУМОМ і оголошений (§3.5): QR-сканер
    # потребує темних модулів на світлому полі незалежно від теми глядача — токен
    # поверхні зробив би код нечитним для камери в темній темі. Allowlist-запис
    # у `gaia_lint.rake` парний до цього коментаря.
    def render_qr_block
      div(class: "flex justify-center p-6 bg-white w-fit mx-auto") do
        raw safe(qr_svg)
      end
    end

    # Секрет ручного введення — для пристроїв без камери. `font-mono` +
    # групування по 4 — так його читають із екрана в телефон.
    def render_secret_block
      div(class: "text-center space-y-2") do
        p(class: "text-mini text-gaia-text-muted uppercase tracking-widest") { t(".secret_label") }
        code(class: "text-tiny text-gaia-primary-strong tracking-[0.3em] break-all") do
          @user.otp_secret.to_s.scan(/.{1,4}/).join(" ")
        end
      end
    end

    def render_confirm_form
      form_with(url: mfa_setup_path, method: :patch, class: "space-y-4 pt-4 border-t border-gaia-border-strong") do |f|
        if @error.present?
          div(class: "p-3 border border-status-danger bg-status-danger text-status-danger-text " \
                     "text-tiny uppercase tracking-widest text-center", role: "alert") { @error }
        end

        div(class: "space-y-2") do
          label(for: f.field_id(:otp_code), class: "text-tiny text-gaia-text-muted uppercase tracking-widest") { t(".confirm_label") }
          f.text_field :otp_code, class: input_classes, placeholder: "000000",
                                  autofocus: true, autocomplete: "one-time-code", inputmode: "numeric"
        end

        button(type: "submit", class: "px-6 py-2 bg-gaia-primary/10 border border-gaia-primary-strong text-tiny text-gaia-primary-strong " \
                                      "uppercase tracking-widest hover:bg-gaia-primary hover:text-gaia-primary-text " \
                                      "focus-visible:outline-none focus-visible:ring-2 " \
                                      "focus-visible:ring-gaia-primary-strong transition-all") do
          t(".activate")
        end
      end
    end

    def input_classes
      "w-full bg-gaia-input-bg border border-gaia-input-border text-gaia-input-text p-4 font-mono text-sm " \
        "focus-visible:border-gaia-primary-strong outline-none transition-all"
    end

    def qr_svg
      RQRCode::QRCode.new(@user.otp_provisioning_uri).as_svg(
        module_size: 4, color: "000", use_path: true, viewbox: true
      )
    end
  end
end
