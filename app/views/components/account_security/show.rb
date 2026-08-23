# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module AccountSecurity
  class Show < ApplicationComponent
    # @param password_error [String, nil] помилка ПОТОЧНОГО сабміту форми пароля.
    #   [SEC.25] Доти ці три відмови (`current_invalid` · `too_short` · `mismatch`)
    #   їхали `redirect_to … error:`, тобто викидали людину з форми зі стертими
    #   полями — при тому, що сусідній `PasswordsController` ту саму задачу
    #   розв'язував правильно: лишав у формі з 422. Асиметрія, не задум.
    # @param erasure_error [String, nil] помилка ПОТОЧНОГО сабміту форми стирання
    #   [SEC.18]. Власний слот, а не реюз `password_error`: спільний показав би
    #   відмову стирання над полями зміни пароля — у секції, якої людина не чіпала.
    def initialize(user:, password_error: nil, erasure_error: nil)
      @user = user
      @password_error = password_error
      @erasure_error = erasure_error
    end

    def view_template
      div(class: "max-w-4xl mx-auto space-y-8") do
        render_header
        render_mfa_section
        render_password_section
        render_data_export_section
        render_erasure_section
      end
    end

    private

    def render_header
      div(class: "p-6 border border-gaia-border bg-gaia-surface") do
        h2(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted") { t(".heading") }
        p(class: "text-xs text-gaia-text-muted mt-2") { t(".subtitle") }
      end
    end

    # --- MFA СЕКЦІЯ ---
    # ✅ [S6.21] Toggle ПОВЕРНУВСЯ 2026-08-20 разом із verify-on-login — рівно як
    # interim і обіцяв. Увімкнення веде в setup-флоу (секрет → QR → verify), а не
    # піднімає прапорець сліпо; вимкнення тримає step-up (current_password).
    def render_mfa_section
      div(class: "p-6 border border-gaia-border bg-gaia-surface space-y-6") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".mfa.heading") }

        if @user.mfa_enabled?
          p(class: "text-tiny text-gaia-primary-strong") { t(".mfa.enabled_with_remaining", count: @user.recovery_codes_remaining) }
          p(class: "text-mini text-gaia-text-muted") { t(".mfa.recovery_warning") }

          render_rotate_codes_form

          form_with(url: account_security_mfa_path, method: :patch, class: "space-y-4") do |f|
            if @user.password_digest.present?
              div(class: "space-y-2") do
                label(for: f.field_id(:current_password),
                      class: "text-tiny text-gaia-text-muted uppercase tracking-widest") { t(".password.current_label") }
                f.password_field :current_password, class: input_classes, required: true
              end
            end
            button(type: "submit", class: "px-6 py-2 border border-status-danger-accent text-tiny " \
                                          "text-status-danger-accent uppercase tracking-widest " \
                                          "hover:bg-status-danger hover:text-status-danger-text focus-visible:outline-none " \
                                          "focus-visible:ring-2 focus-visible:ring-gaia-primary-strong transition-all") do
              t(".mfa.disable_button")
            end
          end
        else
          p(class: "text-tiny text-gaia-text-muted") { t(".mfa.disabled_hint") }
          button_to t(".mfa.enable_button"), mfa_setup_path, method: :post,
                                                            class: "px-6 py-2 bg-gaia-primary/10 border border-gaia-primary-strong text-tiny text-gaia-primary-strong " \
                                                                   "uppercase tracking-widest hover:bg-gaia-primary hover:text-gaia-primary-text " \
                                                                   "focus-visible:outline-none focus-visible:ring-2 " \
                                                                   "focus-visible:ring-gaia-primary-strong transition-all"
        end
      end
    end

    # [S6.21] Ротація recovery-набору: «загубив аркуш, телефон живий» — новий
    # набір без пересканування QR. Step-up дзеркалить disable-форму (ротація
    # знецінює збережені коди, вкрадена сесія не сміє робити це мовчки).
    # Гілка без поля лишається дзеркалом контролерного гарда: акаунт без
    # `password_digest` сьогодні не народжується, тож вона недосяжна.
    def render_rotate_codes_form
      form_with(url: mfa_recovery_codes_path, method: :post, class: "space-y-4") do |f|
        if @user.password_digest.present?
          div(class: "space-y-2") do
            label(for: f.field_id(:current_password),
                  class: "text-tiny text-gaia-text-muted uppercase tracking-widest") { t(".password.current_label") }
            f.password_field :current_password, class: input_classes, required: true
          end
        end
        button(type: "submit", class: "px-6 py-2 border border-gaia-primary-strong text-tiny " \
                                      "text-gaia-primary-strong uppercase tracking-widest " \
                                      "hover:bg-gaia-primary hover:text-gaia-primary-text " \
                                      "focus-visible:outline-none focus-visible:ring-2 " \
                                      "focus-visible:ring-gaia-primary-strong transition-all") do
          t(".mfa.rotate_codes_button")
        end
      end
    end

    # --- ПАРОЛЬ СЕКЦІЯ ---
    def render_password_section
      div(class: "p-6 border border-gaia-border bg-gaia-surface space-y-6") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-4") { t(".password.heading") }

        if @user.password_digest.present?
          p(class: "text-tiny text-gaia-primary-strong mb-4") { t(".password.set_ok") }
        else
          p(class: "text-tiny text-status-warning-accent mb-4") { t(".password.not_set") }
        end

        # [UI.7] `form_with` без скоупу: контролер читає `params[:current_password]`
        # та `[:new_password]` плоско, і жодне з цих імен не є атрибутом `User`.
        form_with(url: account_security_password_path, method: :patch, class: "space-y-4") do
          render_password_error

          if @user.password_digest.present?
            field_container(t(".password.current_label"), "current_password") do |id|
              input(id: id, type: "password", name: "current_password", class: input_classes, required: true)
            end
          end

          field_container(t(".password.new_label"), "new_password") do |id|
            input(id: id, type: "password", name: "new_password", class: input_classes, required: true, minlength: "12")
          end

          field_container(t(".password.confirm_label"), "new_password_confirmation") do |id|
            input(id: id, type: "password", name: "new_password_confirmation", class: input_classes, required: true, minlength: "12")
          end

          button(type: "submit", class: "px-6 py-2 bg-gaia-primary/10 border border-gaia-primary-strong text-tiny text-gaia-primary-strong uppercase tracking-widest hover:bg-gaia-primary hover:text-gaia-primary-text transition-all") do
            @user.password_digest.present? ? t(".password.change_submit") : t(".password.set_submit")
          end
        end
      end
    end

    # [SEC.25] Помилка сабміту стоїть У ФОРМІ, над полями — та сама форма, що вже
    # вживається в `Sessions::New` і `Passwords::Reset`. `role="alert"` обов'язковий:
    # вузол приходить разом із відповіддю, і без нього AT його не оголосить.
    def render_password_error
      return if @password_error.blank?

      div(class: tokens(
        "p-3 border border-status-danger bg-status-danger text-status-danger-text",
        "text-tiny uppercase tracking-widest text-center"
      ), role: "alert") do
        @password_error
      end
    end

    # --- ЕКСПОРТ ДАНИХ (GDPR Art.15 доступ / Art.20 портованість) ---
    # 🔴 [SEC.18] Це ДВЕРІ до вже відвантаженого механізму, не новий механізм.
    # Маршрут `account_security_data_export` живе з 2026-08-20, а посилань на
    # нього в `app/views/` було НУЛЬ — тобто субʼєкт даних міг дістатись лише
    # прямим URL. На комплаєнс-поверхні «сервіс відвантажено» і «людина може
    # ним скористатись» — різні твердження, і зливати їх найдорожче саме тут:
    # Art.12 self-service не вимагає, але від його наявності залежить, скільки
    # місячного строку відповіді зʼїдає ручна робота оператора.
    #
    # ⚠️ Звичайний `a`, а НЕ `button_to`: екшен — GET, ідемпотентний, нічого не
    # мутує (`send_data` зі зліпка). Правило UI.7 вимагає форму для ДІЙ, а не
    # для завантаження; загортати це у форму означало б оголосити мутацію, якої
    # немає. Дзеркальна половина — стирання — живе окремою секцією нижче
    # (`render_erasure_section`, ⚖️ founder 2026-08-21): вона МУТУЄ й незворотна,
    # тож іде формою зі step-up, а не посиланням.
    def render_data_export_section
      div(class: "p-6 border border-gaia-border bg-gaia-surface") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-4") { t(".data_export.heading") }
        p(class: "text-tiny text-gaia-text-muted mb-4") { t(".data_export.hint") }

        a(href: account_security_data_export_path,
          class: "inline-block text-mini text-gaia-primary-strong uppercase tracking-widest hover:text-gaia-text-strong transition-colors border border-gaia-border-strong px-3 py-1 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong") do
          t(".data_export.button")
        end
      end
    end

    # --- СТИРАННЯ АКАУНТА (GDPR Art.17 erasure) ---
    # 🔴 [SEC.18, ⚖️ founder 2026-08-21] Це ДВЕРІ до вже відвантаженого механізму:
    # `Gdpr::AnonymizeUserService` живе з 2026-08-20 із нулем викликачів, бо форма
    # запобіжника була відкритим присудом. Обрано step-up на пароль — той самий
    # зразок, що вже стоїть на `toggle_mfa` disable, тобто нових концепцій нуль.
    #
    # ⚠️ Секція рендериться ЛИШЕ для акаунта з паролем, і це дзеркало гарда в
    # контролері, а не косметика: акт незворотний, тож без спільного секрета
    # доказу наміру не існує, і кнопка вела б у гарантовану відмову. Акаунта без
    # пароля в дереві не буває за побудовою (валідація безумовна), тож цей
    # `return` — недосяжний запобіжник, а не гілка під наявний стан.
    def render_erasure_section
      return if @user.password_digest.blank?

      div(class: "p-6 border border-status-danger bg-gaia-surface space-y-4") do
        h3(class: "text-tiny uppercase tracking-widest text-status-danger-accent mb-4") { t(".erasure.heading") }
        p(class: "text-tiny text-gaia-text-muted mb-4") { t(".erasure.hint") }

        # [UI.7] `form_with` без скоупу — `current_password` не є атрибутом `User`,
        # тож контролер читає його плоско (дзеркало форми пароля вище).
        form_with(url: account_security_erase_path, method: :delete, class: "space-y-4") do
          render_erasure_error

          field_container(t(".erasure.current_label"), "erasure_current_password") do |id|
            input(id: id, type: "password", name: "current_password", class: input_classes, required: true)
          end

          button(type: "submit", class: "px-6 py-2 bg-status-danger border border-status-danger text-tiny text-status-danger-text uppercase tracking-widest hover:bg-status-danger-accent transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-status-danger-accent") do
            t(".erasure.submit")
          end
        end
      end
    end

    # [SEC.18] Дзеркало `render_password_error` — власний слот, бо відмова мусить
    # зʼявитись У СВОЇЙ формі; `role="alert"` обовʼязковий (вузол приходить разом
    # із відповіддю, і без нього AT його не оголосить).
    def render_erasure_error
      return if @erasure_error.blank?

      div(class: tokens(
        "p-3 border border-status-danger bg-status-danger text-status-danger-text",
        "text-tiny uppercase tracking-widest text-center"
      ), role: "alert") do
        @erasure_error
      end
    end

    # --- ПРОВАЙДЕРИ СЕКЦІЯ ---
    # [UI.3] Мітка ЗВʼЯЗАНА з полем: `for` ⟷ `id`, обидва з одного дому
    # (`field_id_for`). Доти `<label>` і `<input>` були сиблінгами без жодної
    # асоціації — ні явної, ні через вкладеність, — тож скрінрідер не називав поле
    # взагалі (WCAG 1.3.1). Тут форма йде `form_with(url:)` БЕЗ моделі, тобто білдера
    # в блоці немає й `id` не згенерується сам; блок дістає його аргументом, щоб
    # рукописних копій не було двох.
    def field_container(label_text, name, &)
      field_id = field_id_for(name)

      div(class: "space-y-2") do
        label(for: field_id, class: "text-mini text-gaia-text-muted uppercase tracking-widest block") { label_text }
        yield(field_id)
      end
    end

    def input_classes
      "w-full bg-gaia-input-bg border border-gaia-input-border text-compact font-mono text-gaia-input-text px-4 py-3 focus-visible:border-gaia-primary-strong focus-visible:outline-none transition-colors"
    end
  end
end
