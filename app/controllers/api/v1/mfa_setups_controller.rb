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
          codes = current_user.generate_recovery_codes!

          respond_to do |format|
            # JSON-клієнт дістає набір РАЗОМ із підтвердженням — це його єдиний
            # показ (наступний GET reveal-сторінки без маркера редиректить).
            format.json { render json: { message: t("account_security.mfa.enabled"), mfa_enabled: true, recovery_codes: codes }, status: :ok }
            # [S6.21] PRG на reveal-сторінку: КОДИ в cookie не їдуть (маркер
            # булевий), сам набір читається з БД під автентифікацією рівно раз.
            format.html do
              session[:mfa_codes_reveal] = true
              redirect_to mfa_recovery_codes_path, status: :see_other, security: t("account_security.mfa.enabled")
            end
          end
        else
          respond_to do |format|
            format.json { render json: { error: t("account_security.mfa_setup.invalid_code") }, status: :unprocessable_content }
            format.html { render_setup_page(error: t("account_security.mfa_setup.invalid_code"), status: :unprocessable_content) }
          end
        end
      end

      # --- ОДНОРАЗОВИЙ ПОКАЗ RECOVERY-НАБОРУ ---
      # GET /account_security/mfa_recovery_codes
      #
      # [S6.21] Показ РІВНО РАЗ: `session.delete` читає і знімає маркер одним
      # рухом, тож повторний GET (закладка, Back, чуже плече) редиректить на
      # екран безпеки. Не flash (сесійний cookie — не місце секретам) і не
      # постійна секція show (набір у БД plaintext — постійний показ розширює
      # вікно плеча); повторний показ існує лише як ротація НОВОГО набору (POST).
      def recovery_codes
        return redirect_to account_security_path, status: :see_other unless current_user.mfa_enabled?
        return redirect_to account_security_path, status: :see_other unless session.delete(:mfa_codes_reveal)

        render_dashboard(
          title: t("account_security.recovery_codes.title"),
          component: AccountSecurity::RecoveryCodes.new(codes: current_user.parsed_recovery_codes)
        )
      end

      # --- РОТАЦІЯ RECOVERY-НАБОРУ ---
      # POST /account_security/mfa_recovery_codes
      #
      # [S6.21] «Загубив аркуш, телефон живий»: ротація лишає TOTP-секрет
      # недоторканим (disable→enable змусив би пересканувати QR). Step-up —
      # дзеркало disable-гілки `toggle_mfa`: ротація ЗНЕЦІНЮЄ збережені коди,
      # тобто вкрадена сесія не сміє робити це мовчки. Гард на `password_digest`
      # лишається fail-OPEN за формою, але недосяжним: акаунт без пароля не
      # народжується (валідація безумовна).
      def rotate_recovery_codes
        return redirect_to account_security_path, status: :see_other unless current_user.mfa_enabled?

        if current_user.password_digest.present? &&
           !current_user.authenticate(params[:current_password].to_s)
          return respond_to do |format|
            format.json { render json: { error: t("account_security.password.current_invalid") }, status: :unprocessable_content }
            format.html { redirect_to account_security_path, status: :see_other, error: t("account_security.password.current_invalid") }
          end
        end

        codes = current_user.generate_recovery_codes!

        respond_to do |format|
          format.json { render json: { message: t("account_security.recovery_codes.rotated"), recovery_codes: codes }, status: :ok }
          format.html do
            session[:mfa_codes_reveal] = true
            redirect_to mfa_recovery_codes_path, status: :see_other, security: t("account_security.recovery_codes.rotated")
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
