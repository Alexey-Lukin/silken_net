# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class AccountSecurityController < BaseController
      # --- СТОРІНКА БЕЗПЕКИ АКАУНТУ ---
      # GET /account_security
      def show
        @user = current_user
        @identities = @user.identities.order(created_at: :asc).to_a

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

      # --- DSAR-ЕКСПОРТ [SEC.18] ---
      # GET /account_security/data_export — self-service право доступу (Art.15)
      # у портованій формі (Art.20): файл-attachment, не сторінка. Периметр і
      # межі (що НЕ віддається і чому) — докблок `Gdpr::DataExportService`.
      def data_export
        payload = Gdpr::DataExportService.call(current_user)

        send_data JSON.pretty_generate(payload),
                  filename: "silkennet-data-export-#{Date.current.iso8601}.json",
                  type: "application/json",
                  disposition: "attachment"
      end

      # --- СТИРАННЯ АКАУНТА [SEC.18] ---
      # DELETE /account_security/erase — self-service право на стирання (Art.17).
      # ⚖️ founder 2026-08-21: запобіжник = step-up на пароль, той самий, що вже
      # стоїть на `toggle_mfa` disable нижче. Механізм не новий — `AnonymizeUserService`
      # відвантажено 2026-08-20 із нулем викликачів; це його ДВЕРІ.
      #
      # 🔴 Гард fail-CLOSED, і відмінність від `toggle_mfa` тут НАВМИСНА. Там
      # акаунт без пароля (OAuth-only) step-up МИНАЄ — бо спільного секрета не
      # існує, а дія оборотна. Тут дія НЕЗВОРОТНА (tombstone + знищення сесій та
      # identities), тож відсутність доказу мусить означати ВІДМОВУ, а не
      # пропуск: інакше перший passwordless-вхід тихо відкриє незворотний акт
      # будь-кому з вкраденою cookie (`04_03 §1.2` називає цю форму такою, що
      # «чекає свого тригера»). Людський шлях для таких акаунтів лишається —
      # `docs/protocols/legal/gdpr_runbook.md` §2, і місячний строк Art.12(3)
      # він витримує.
      def erase_account
        unless current_user.password_digest.present? &&
               current_user.authenticate(params[:current_password].to_s)
          return respond_to do |format|
            format.json { render json: { error: t("account_security.erasure.password_invalid") }, status: :unprocessable_content }
            format.html { render_erasure_error(t("account_security.erasure.password_invalid")) }
          end
        end

        Gdpr::AnonymizeUserService.call(current_user)
        # Симетрично до `establish_session`: після tombstone сесія не має чого
        # ідентифікувати, а `session[:ps]` вказував би на знятий digest.
        reset_session

        respond_to do |format|
          format.json { render json: { message: t("account_security.erasure.done") }, status: :ok }
          format.html { redirect_to login_path, status: :see_other, security: t("account_security.erasure.done") }
        end
      end

      # --- ВВІМКНЕННЯ/ВИМКНЕННЯ MFA ---
      # PATCH /account_security/mfa
      def toggle_mfa
        if current_user.mfa_enabled?
          # [STEP-UP AUTH FIX]: Disabling MFA is a critical downgrade — if a
          # session is hijacked (XSS, stolen cookie) the attacker could turn
          # off the second factor silently. Require fresh proof of the
          # account password before lowering the security level. Users who
          # signed in purely via OAuth (no local password) keep the previous
          # behaviour, since there is no shared secret to challenge with.
          if current_user.password_digest.present? &&
             !current_user.authenticate(params[:current_password].to_s)
            return respond_to do |format|
              format.json { render json: { error: t("account_security.password.current_invalid") }, status: :unprocessable_content }
              format.html { redirect_to account_security_path, status: :see_other, error: t("account_security.password.current_invalid") }
            end
          end

          current_user.update!(otp_required_for_login: false, recovery_codes: nil)
          respond_to do |format|
            format.json { render json: { message: t("account_security.mfa.disabled"), mfa_enabled: false }, status: :ok }
            format.html { redirect_to account_security_path, status: :see_other, security: t("account_security.mfa.disabled") }
          end
        else
          # [S6.21] Увімкнення йде ЛИШЕ setup-флоу (секрет + verify свіжого коду):
          # сліпе підняття прапорця тут було б поверненням заявки без механізму —
          # рівно того, що 501-гейт і закривав до появи verify-on-login.
          respond_to do |format|
            format.json { render json: { error: t("account_security.mfa_setup.use_setup_flow"), code: "mfa_setup_required" }, status: :conflict }
            format.html { redirect_to mfa_setup_path, status: :see_other }
          end
        end
      end

      # --- ВІДВ'ЯЗКА ПРОВАЙДЕРА ---
      # DELETE /account_security/identities/:id
      def unlink_identity
        identity = current_user.identities.find(params[:id])

        # Не можна відв'язати всіх провайдерів, якщо немає пароля
        if current_user.password_digest.blank? && current_user.identities.active.count <= 1
          respond_to do |format|
            format.json { render json: { error: t("account_security.identity.cannot_unlink_last") }, status: :unprocessable_content }
            format.html { redirect_to account_security_path, status: :see_other, error: t("account_security.identity.set_password_first") }
          end
          return
        end

        identity.destroy!

        respond_to do |format|
          format.json { render json: { message: t("account_security.identity.unlinked_json", provider: identity.provider) }, status: :ok }
          format.html { redirect_to account_security_path, status: :see_other, security: t("account_security.identity.unlinked_flash", provider: identity.provider.titleize) }
        end
      end

      # --- БЛОКУВАННЯ ПРОВАЙДЕРА ---
      # PATCH /account_security/identities/:id/lock
      def lock_identity
        identity = current_user.identities.find(params[:id])
        identity.lock!

        respond_to do |format|
          format.json { render json: { message: t("account_security.identity.locked_json", provider: identity.provider) }, status: :ok }
          format.html { redirect_to account_security_path, status: :see_other, security: t("account_security.identity.locked_flash", provider: identity.provider.titleize) }
        end
      end

      # --- РОЗБЛОКУВАННЯ ПРОВАЙДЕРА ---
      # PATCH /account_security/identities/:id/unlock
      def unlock_identity
        identity = current_user.identities.find(params[:id])
        identity.unlock!

        respond_to do |format|
          format.json { render json: { message: t("account_security.identity.unlocked_json", provider: identity.provider) }, status: :ok }
          format.html { redirect_to account_security_path, status: :see_other, security: t("account_security.identity.unlocked_flash", provider: identity.provider.titleize) }
        end
      end

      # --- ЗМІНА ПАРОЛЯ ---
      # PATCH /account_security/password
      def change_password
        # 🔴 [SEC.25] Усі три відмови нижче — ВАЛІДАЦІЯ поточного сабміту, тож людина
        # лишається у формі з 422, а не летить редиректом на ту саму сторінку зі
        # стертими полями. Форма запозичена не з чужої дизайн-системи, а в сусіда:
        # `PasswordsController#update` на тій самій задачі (`too_short`/`mismatch`)
        # робив так від початку — тут була асиметрія, не задум.
        if current_user.password_digest.present? && !current_user.authenticate(params[:current_password])
          respond_to do |format|
            format.json { render json: { error: t("account_security.password.current_invalid") }, status: :unprocessable_content }
            format.html { render_password_error(t("account_security.password.current_invalid")) }
          end
          return
        end

        if params[:new_password].to_s.length < 12
          respond_to do |format|
            format.json { render json: { error: t("account_security.password.too_short_json") }, status: :unprocessable_content }
            format.html { render_password_error(t("account_security.password.too_short_flash")) }
          end
          return
        end

        if params[:new_password] != params[:new_password_confirmation]
          respond_to do |format|
            format.json { render json: { error: t("account_security.password.mismatch") }, status: :unprocessable_content }
            format.html { render_password_error(t("account_security.password.mismatch")) }
          end
          return
        end

        current_user.update!(password: params[:new_password])

        # [SEC.16] Свіжий salt-stamp для ПОТОЧНОЇ cookie-сесії — ініціатор зміни
        # лишається залогіненим; всі інші cookie гаснуть самі (stale salt у
        # authenticate_user!). Звірка user_id: Bearer-запит із ЧУЖИМ cookie-jar
        # не має штампувати чужу сесію.
        if session[:user_id].to_s == current_user.id.to_s
          session[:ps] = current_user.session_salt_stamp
        end

        # [SECURITY] Revoke every other Rails session — a password change is a
        # security event; lingering sessions on other devices should not retain
        # access. We keep the row backing the current request so the user is
        # not bounced out of the dashboard mid-flow.
        keep_id = session_record_id_for_current_request
        scope = current_user.sessions
        scope = scope.where.not(id: keep_id) if keep_id
        scope.destroy_all

        respond_to do |format|
          format.json { render json: { message: t("account_security.password.updated_json") }, status: :ok }
          format.html { redirect_to account_security_path, status: :see_other, security: t("account_security.password.updated_flash") }
        end
      end

      private

      # ✅ [S6.21] 501-гейт «mfa_not_implemented» ЗНЯТО 2026-08-20 разом із появою
      # verify-on-login (`MfaChallengesController`) — рівно так, як його контракт
      # і вимагав. Увімкнення тепер має механізм і йде setup-флоу
      # (`MfaSetupsController`: секрет → QR → verify → прапорець), тож enable-гілка
      # `toggle_mfa` шле туди, а не піднімає прапорець сліпо.

      # [SEC.25] Один дім посадки для валідаційних відмов форми пароля: та сама
      # сторінка, те саме місце, 422 — дзеркало `PasswordsController#update`.
      # `status:` тут несучий, а не косметика: на `200` без редиректу Turbo
      # відповідь ВИКИДАЄ (`04_03 §2.2а`), тобто форма виглядала б мертвою.
      def render_password_error(message)
        render_dashboard(
          title: t("account_security.title"),
          component: AccountSecurity::Show.new(
            user: current_user,
            identities: current_user.identities.order(created_at: :asc),
            password_error: message
          ),
          status: :unprocessable_content
        )
      end

      # [SEC.18] Власна посадка, а не реюз `render_password_error`: помилка
      # мусить зʼявитись У СВОЇЙ формі. Спільний слот показав би відмову
      # стирання над полями зміни пароля — тобто в секції, якої людина не
      # чіпала, і читалась би вона як інший клас події (`04_03 §2.2б`).
      def render_erasure_error(message)
        render_dashboard(
          title: t("account_security.title"),
          component: AccountSecurity::Show.new(
            user: current_user,
            identities: current_user.identities.order(created_at: :asc),
            erasure_error: message
          ),
          status: :unprocessable_content
        )
      end

      # We don't track the current-request Session id directly. Approximate by
      # the most recent row matching the request's IP+user-agent, falling back
      # to the newest row. Returns nil when the user has zero session rows
      # (e.g. pure Bearer-token clients).
      def session_record_id_for_current_request
        scope = current_user.sessions
        match = scope.find_by(ip_address: request.remote_ip, user_agent: request.user_agent.presence)
        (match || scope.order(created_at: :desc).first)&.id
      end
    end
  end
end
