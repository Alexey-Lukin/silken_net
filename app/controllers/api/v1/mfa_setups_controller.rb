# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    # [S6.21] Setup-флоу TOTP: провижн секрета → QR/URI → verify-код → активація.
    #
    # Прапорець `otp_required_for_login` піднімається ЛИШЕ тут і ЛИШЕ після того,
    # як користувач довів володіння authenticator-ом (verify свіжого коду) —
    # сліпого «увімкнути» не існує, бо саме воно й було security-theatre
    # (заявка без механізму, закрита 501-гейтом 2026-08-17).
    class MfaSetupsController < BaseController
      # --- СТАРТ / РЕСТАРТ SETUP ---
      # POST /account_security/mfa_setup
      def create
        return render_already_enabled if current_user.mfa_enabled?

        current_user.provision_otp_secret!
        redirect_to mfa_setup_path, status: :see_other
      end

      # --- QR + ФОРМА ПІДТВЕРДЖЕННЯ ---
      # GET /account_security/mfa_setup
      def show
        return render_already_enabled if current_user.mfa_enabled?
        # Прямий GET без провижну — назад на екран безпеки: сторінка без секрета
        # не має що показувати, а провижнити на GET означало б мутацію читанням.
        return redirect_to account_security_path if current_user.otp_secret.blank?

        render_setup_page
      end

      # --- АКТИВАЦІЯ (verify свіжого коду) ---
      # PATCH /account_security/mfa_setup
      def update
        return render_already_enabled if current_user.mfa_enabled?
        return redirect_to account_security_path if current_user.otp_secret.blank?

        if current_user.verify_totp!(params[:otp_code])
          current_user.update!(otp_required_for_login: true)
          # Rotation при активації: старий набір (від попередньої спроби чи
          # знятого MFA) не сміє переживати нову заявку.
          current_user.generate_recovery_codes!

          respond_to do |format|
            format.json { render json: { message: t("account_security.mfa.enabled"), mfa_enabled: true }, status: :ok }
            format.html { redirect_to account_security_path, status: :see_other, security: t("account_security.mfa.enabled") }
          end
        else
          respond_to do |format|
            format.json { render json: { error: t("account_security.mfa_setup.invalid_code") }, status: :unprocessable_content }
            format.html { render_setup_page(error: t("account_security.mfa_setup.invalid_code"), status: :unprocessable_content) }
          end
        end
      end

      private

      def render_setup_page(error: nil, status: :ok)
        render_dashboard(
          title: t("account_security.mfa_setup.title"),
          component: AccountSecurity::MfaSetup.new(user: current_user, error: error),
          status: status
        )
      end

      def render_already_enabled
        respond_to do |format|
          format.json { render json: { error: t("account_security.mfa_setup.already_enabled") }, status: :conflict }
          format.html { redirect_to account_security_path, status: :see_other }
        end
      end
    end
  end
end
