# frozen_string_literal: true

module Api
  module V1
    class AccountSecurityController < BaseController
      # --- СТОРІНКА БЕЗПЕКИ АКАУНТУ ---
      # GET /api/v1/account_security
      def show
        @user = current_user
        @identities = @user.identities.order(created_at: :asc)

        respond_to do |format|
          format.json do
            render json: {
              mfa_enabled: @user.mfa_enabled?,
              recovery_codes_remaining: @user.recovery_codes_remaining,
              has_password: @user.password_digest.present?,
              identities: @identities.map { |i|
                {
                  id: i.id,
                  provider: i.provider,
                  uid: i.uid,
                  primary: i.primary?,
                  locked: i.locked?,
                  created_at: i.created_at
                }
              }
            }
          end
          format.html do
            render_dashboard(
              title: t("account_security.title"),
              component: AccountSecurity::Show.new(user: @user, identities: @identities)
            )
          end
        end
      end

      # --- ВВІМКНЕННЯ/ВИМКНЕННЯ MFA ---
      # PATCH /api/v1/account_security/mfa
      def toggle_mfa
        if current_user.mfa_enabled?
          current_user.update!(otp_required_for_login: false, recovery_codes: nil)
          respond_to do |format|
            format.json { render json: { message: t("account_security.mfa.disabled"), mfa_enabled: false }, status: :ok }
            format.html { redirect_to api_v1_account_security_path, notice: t("account_security.mfa.disabled") }
          end
        else
          codes = current_user.generate_recovery_codes!
          current_user.update!(otp_required_for_login: true)
          respond_to do |format|
            format.json { render json: { message: t("account_security.mfa.enabled"), mfa_enabled: true, recovery_codes: codes }, status: :ok }
            format.html { redirect_to api_v1_account_security_path, notice: t("account_security.mfa.enabled_with_codes") }
          end
        end
      end

      # --- ВІДВ'ЯЗКА ПРОВАЙДЕРА ---
      # DELETE /api/v1/account_security/identities/:id
      def unlink_identity
        identity = current_user.identities.find(params[:id])

        # Не можна відв'язати всіх провайдерів, якщо немає пароля
        if current_user.password_digest.blank? && current_user.identities.active.count <= 1
          respond_to do |format|
            format.json { render json: { error: t("account_security.identity.cannot_unlink_last") }, status: :unprocessable_content }
            format.html { redirect_to api_v1_account_security_path, alert: t("account_security.identity.set_password_first") }
          end
          return
        end

        identity.destroy!

        respond_to do |format|
          format.json { render json: { message: t("account_security.identity.unlinked_json", provider: identity.provider) }, status: :ok }
          format.html { redirect_to api_v1_account_security_path, notice: t("account_security.identity.unlinked_flash", provider: identity.provider.titleize) }
        end
      end

      # --- БЛОКУВАННЯ ПРОВАЙДЕРА ---
      # PATCH /api/v1/account_security/identities/:id/lock
      def lock_identity
        identity = current_user.identities.find(params[:id])
        identity.lock!

        respond_to do |format|
          format.json { render json: { message: t("account_security.identity.locked_json", provider: identity.provider) }, status: :ok }
          format.html { redirect_to api_v1_account_security_path, notice: t("account_security.identity.locked_flash", provider: identity.provider.titleize) }
        end
      end

      # --- РОЗБЛОКУВАННЯ ПРОВАЙДЕРА ---
      # PATCH /api/v1/account_security/identities/:id/unlock
      def unlock_identity
        identity = current_user.identities.find(params[:id])
        identity.unlock!

        respond_to do |format|
          format.json { render json: { message: t("account_security.identity.unlocked_json", provider: identity.provider) }, status: :ok }
          format.html { redirect_to api_v1_account_security_path, notice: t("account_security.identity.unlocked_flash", provider: identity.provider.titleize) }
        end
      end

      # --- ЗМІНА ПАРОЛЯ ---
      # PATCH /api/v1/account_security/password
      def change_password
        if current_user.password_digest.present? && !current_user.authenticate(params[:current_password])
          respond_to do |format|
            format.json { render json: { error: t("account_security.password.current_invalid") }, status: :unprocessable_content }
            format.html { redirect_to api_v1_account_security_path, alert: t("account_security.password.current_invalid") }
          end
          return
        end

        if params[:new_password].to_s.length < 12
          respond_to do |format|
            format.json { render json: { error: t("account_security.password.too_short_json") }, status: :unprocessable_content }
            format.html { redirect_to api_v1_account_security_path, alert: t("account_security.password.too_short_flash") }
          end
          return
        end

        if params[:new_password] != params[:new_password_confirmation]
          respond_to do |format|
            format.json { render json: { error: t("account_security.password.mismatch") }, status: :unprocessable_content }
            format.html { redirect_to api_v1_account_security_path, alert: t("account_security.password.mismatch") }
          end
          return
        end

        current_user.update!(password: params[:new_password])

        respond_to do |format|
          format.json { render json: { message: t("account_security.password.updated_json") }, status: :ok }
          format.html { redirect_to api_v1_account_security_path, notice: t("account_security.password.updated_flash") }
        end
      end
    end
  end
end
