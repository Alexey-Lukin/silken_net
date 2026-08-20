# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Settings
  class Show < ApplicationComponent
    def initialize(organization:)
      @organization = organization
    end

    def view_template
      div(class: "space-y-8") do
        header_section
        div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
          div(class: "xl:col-span-2") do
            render_settings_form
          end
          div(class: "space-y-6") do
            render_identity_vault
            render_metadata
          end
        end
      end
    end

    private

    def header_section
      div(class: "flex justify-between items-end mb-4") do
        div do
          h3(class: "text-tiny uppercase tracking-[0.4em] text-gaia-text-muted") { t(".heading") }
          p(class: "text-xs text-gaia-text-muted mt-1") { t(".subtitle") }
        end
      end
    end

    def render_settings_form
      div(class: "p-6 border border-gaia-border bg-gaia-surface") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-6") { t(".config.heading") }

        # [UI.7] `form_with`: токен і `_method=patch` приходять самі.
        # ⚠️ `multipart: true` ЯВНО, і це не перестраховка: авто-детект `form_with`
        # спрацьовує на БІЛДЕРНОМУ `f.file_field`, а логотип тут — сирий
        # `input(type: "file")`, якого хелпер не бачить. Без цього рядка `enctype`
        # згорнувся б у `urlencoded`, і `organization[logo]` приїхав би РЯДКОМ з
        # іменем файлу замість завантаження. Дзеркало — `firmwares/form.rb`.
        # ⚠️ Скоуп не задаємо `model:`-формою: префікс `organization[...]` тут
        # збігається з `params.require(:organization)`, але `model:` вивів би ще й
        # МАРШРУТ — `organization_path`, для якого PATCH-роуту не існує взагалі.
        form_with(url: settings_path, method: :patch, multipart: true, class: "space-y-6") do
          # [SEC.25] Контролер рендерить цю сторінку на 422 (кривий billing_email,
          # зайнята назва, поріг поза діапазоном), і доти причина нікуди не їхала —
          # `org.errors` бачила лише JSON-гілка.
          render Views::Shared::UI::ErrorSummary.new(messages: @organization.errors.full_messages)

          render_field(t(".fields.org_name"), "organization[name]", @organization.name)
          render_field(t(".fields.billing_email"), "organization[billing_email]", @organization.billing_email, placeholder: "billing@example.org")
          render_field(t(".fields.crypto_address"), "organization[crypto_public_address]", @organization.crypto_public_address, placeholder: "0x...")
          render_field(t(".fields.alert_threshold"), "organization[alert_threshold_critical_z]", @organization.alert_threshold_critical_z, placeholder: "2.5")
          render_field(t(".fields.ai_sensitivity"), "organization[ai_sensitivity]", @organization.ai_sensitivity, placeholder: "0.7")
          render_locale_field
          render_logo_field

          div(class: "pt-4 border-t border-gaia-border") do
            button(type: "submit", class: "px-6 py-2 bg-gaia-primary/10 border border-gaia-primary-strong text-tiny uppercase tracking-widest text-gaia-primary-strong hover:bg-gaia-primary hover:text-gaia-primary-text transition-all") { t(".submit") }
          end
        end
      end
    end

    # [UI.3] `for` ⟷ `id` з одного дому (`field_id_for`): доти мітка й поле були
    # сиблінгами без асоціації, тож скрінрідер поля не називав (WCAG 1.3.1).
    def render_field(label_text, name, value, placeholder: nil)
      field_id = field_id_for(name)

      div(class: "space-y-2") do
        label(for: field_id, class: "text-mini text-gaia-text-muted uppercase tracking-widest block") { label_text }
        input(
          id: field_id,
          type: "text",
          name: name,
          value: value&.to_s,
          placeholder: placeholder,
          class: "w-full bg-gaia-input-bg border border-gaia-input-border text-compact font-mono text-gaia-input-text px-4 py-3 focus-visible:border-gaia-primary-strong focus-visible:outline-none transition-colors"
        )
      end
    end

    # [I18N.1] Мова, якою організація ОТРИМУЄ ПОШТУ (`AlertMailer` шле на
    # `billing_email`). Без цього поля колонка `organizations.locale` не мала б
    # жодного шляху заповнення й лишилась би декоративною назавжди.
    #
    # Перелік ітерує `I18n.available_locales` — п'ята мова з'явиться тут сама,
    # без правки компонента. Ендоніми беруться з базової локалі (їхній єдиний
    # дім, `04_04 §12.2`) і однакові в будь-якому UI за визначенням.
    def render_locale_field
      div(class: "space-y-2") do
        label(class: "text-mini text-gaia-text-muted uppercase tracking-widest block", for: "organization_locale") { t(".fields.locale") }
        select(
          id: "organization_locale",
          name: "organization[locale]",
          class: "w-full bg-gaia-input-bg border border-gaia-input-border text-compact font-mono text-gaia-input-text px-4 py-3 focus-visible:border-gaia-primary-strong focus-visible:outline-none transition-colors"
        ) do
          # Порожнє значення — «не обрано»: пошта піде базовою локаллю. Це не те
          # саме, що явно обрана англійська, і колонка тримає цю різницю.
          option(value: "", selected: @organization.locale.blank?) { t(".fields.locale_unset") }

          I18n.available_locales.each do |code|
            option(value: code.to_s, selected: @organization.locale == code.to_s) do
              I18n.t("locale.available.#{code}")
            end
          end
        end
      end
    end

    def render_logo_field
      div(class: "space-y-2") do
        label(for: "organization_logo", class: "text-mini text-gaia-text-muted uppercase tracking-widest block") { t(".fields.logo") }
        if @organization.logo.attached?
          div(class: "flex items-center gap-4 mb-2") do
            span(class: "text-tiny text-gaia-primary-strong font-mono") { t(".fields.current_logo", filename: @organization.logo.filename) }
          end
        end
        input(
          id: "organization_logo",
          type: "file",
          name: "organization[logo]",
          accept: "image/png,image/jpeg,image/svg+xml",
          class: "w-full bg-gaia-input-bg border border-gaia-input-border text-compact font-mono text-gaia-input-text px-4 py-3 file:mr-4 file:border-0 file:bg-gaia-primary/10 file:text-gaia-primary-strong file:text-tiny file:px-4 file:py-2"
        )
      end
    end

    def render_identity_vault
      div(class: "p-6 border border-gaia-border bg-gaia-surface space-y-6") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted") { t(".vault.heading") }

        div do
          p(class: "text-mini text-gaia-text-muted uppercase mb-2") { t(".vault.address") }
          render Views::Shared::Web3::Address.new(address: @organization.crypto_public_address)
        end

        div(class: "pt-4 border-t border-gaia-border") do
          p(class: "text-mini text-gaia-text-muted uppercase mb-2") { t(".vault.billing") }
          p(class: "text-compact text-gaia-text-subtle") { @organization.billing_email || "N/A" }
        end
      end
    end

    def render_metadata
      div(class: "p-6 border border-gaia-border bg-gaia-primary/5") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-4") { t(".metadata.heading") }
        div(class: "space-y-3 font-mono text-tiny") do
          meta_row(t(".metadata.org_id"), @organization.id)
          meta_row(t(".metadata.created"), @organization.created_at.strftime("%d.%m.%Y"))
          meta_row(t(".metadata.updated"), @organization.updated_at.strftime("%d.%m.%Y %H:%M"))
        end
      end
    end

    def meta_row(label, value)
      div(class: "flex justify-between items-center") do
        span(class: "text-gaia-text-muted uppercase") { label }
        span(class: "text-gaia-text") { value.to_s }
      end
    end
  end
end
