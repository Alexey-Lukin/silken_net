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
              title: "Account Security",
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
            format.json { render json: { message: "MFA вимкнено.", mfa_enabled: false }, status: :ok }
            format.html { redirect_to api_v1_account_security_path, notice: "MFA вимкнено." }
          end
        else
          codes = current_user.generate_recovery_codes!
          current_user.update!(otp_required_for_login: true)
          respond_to do |format|
            format.json { render json: { message: "MFA увімкнено.", mfa_enabled: true, recovery_codes: codes }, status: :ok }
            format.html { redirect_to api_v1_account_security_path, notice: "MFA увімкнено. Збережіть recovery codes!" }
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
            format.json { render json: { error: "Неможливо відв'язати останній метод входу без пароля." }, status: :unprocessable_content }
            format.html { redirect_to api_v1_account_security_path, alert: "Встановіть пароль перед відв'язкою останнього провайдера." }
          end
          return
        end

        identity.destroy!

        respond_to do |format|
          format.json { render json: { message: "Провайдер #{identity.provider} відв'язано." }, status: :ok }
          format.html { redirect_to api_v1_account_security_path, notice: "#{identity.provider.titleize} відв'язано." }
        end
      end

      # --- БЛОКУВАННЯ ПРОВАЙДЕРА ---
      # PATCH /api/v1/account_security/identities/:id/lock
      def lock_identity
        identity = current_user.identities.find(params[:id])
        identity.lock!

        respond_to do |format|
          format.json { render json: { message: "Ідентичність #{identity.provider} заблоковано." }, status: :ok }
          format.html { redirect_to api_v1_account_security_path, notice: "#{identity.provider.titleize} заблоковано." }
        end
      end

      # --- РОЗБЛОКУВАННЯ ПРОВАЙДЕРА ---
      # PATCH /api/v1/account_security/identities/:id/unlock
      def unlock_identity
        identity = current_user.identities.find(params[:id])
        identity.unlock!

        respond_to do |format|
          format.json { render json: { message: "Ідентичність #{identity.provider} розблоковано." }, status: :ok }
          format.html { redirect_to api_v1_account_security_path, notice: "#{identity.provider.titleize} розблоковано." }
        end
      end

      # --- ЗМІНА ПАРОЛЯ ---
      # PATCH /api/v1/account_security/password
      def change_password
        if current_user.password_digest.present? && !current_user.authenticate(params[:current_password])
          respond_to do |format|
            format.json { render json: { error: "Поточний пароль невірний." }, status: :unprocessable_content }
            format.html { redirect_to api_v1_account_security_path, alert: "Поточний пароль невірний." }
          end
          return
        end

        if params[:new_password].to_s.length < 12
          respond_to do |format|
            format.json { render json: { error: "Новий пароль повинен містити мінімум 12 символів." }, status: :unprocessable_content }
            format.html { redirect_to api_v1_account_security_path, alert: "Пароль повинен містити мінімум 12 символів." }
          end
          return
        end

        if params[:new_password] != params[:new_password_confirmation]
          respond_to do |format|
            format.json { render json: { error: "Паролі не співпадають." }, status: :unprocessable_content }
            format.html { redirect_to api_v1_account_security_path, alert: "Паролі не співпадають." }
          end
          return
        end

        current_user.update!(password: params[:new_password])

        respond_to do |format|
          format.json { render json: { message: "Пароль оновлено." }, status: :ok }
          format.html { redirect_to api_v1_account_security_path, notice: "Пароль успішно оновлено." }
        end
      end
    end
  end
end
