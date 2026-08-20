# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Notifications
  class Settings < ApplicationComponent
    # [UI.10] `available_channels` приходить ЗВОВНІ (дім — `Notifications::
    # DeliveryChannels`), бо це факт про платформу, а не про користувача.
    # Дефолт порожній СВІДОМО — fail-closed: компонент, якому забули передати
    # факт, применшує спроможність, а не вигадує її.
    def initialize(user:, available_channels: [])
      @user = user
      @available_channels = Array(available_channels).map(&:to_sym)
    end

    def view_template
      div(class: "space-y-8") do
        header_section
        div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
          div(class: "xl:col-span-2 space-y-6") do
            render_channels_form
          end
          div(class: "space-y-6") do
            render_channels_status
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

    def render_channels_form
      div(class: "p-6 border border-gaia-border bg-gaia-surface") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-6") { t(".channels.heading") }

        # [UI.7] `form_with` БЕЗ скоупу — і це найнебезпечніший сайт конверсії:
        # поля (`phone_number`/`telegram_chat_id`/`push_token`) є колонками `User`,
        # тож `model: current_user` виглядав би природно — а контролер читає їх
        # ПЛОСКО (`params.permit(:phone_number…)`). Під `user[...]` permit віддав би
        # `{}`, `update({})` повернув би **true**, і людина побачила б «збережено»
        # при нулі збережень. Компонентні піни цього не бачать (голий `include`).
        form_with(url: notifications_settings_path, method: :patch, class: "space-y-6") do
          # [SEC.25] Дзеркало `settings#update`: телефон не в E.164 дає 422, і доти
          # сторінка просто перемальовувалась із тим самим значенням у полі.
          render Views::Shared::UI::ErrorSummary.new(messages: @user.errors.full_messages)

          render_field(t(".channels.email_address"), "email", @user.email_address, disabled: true, hint: t(".email_hint"))
          render_field(t(".channels.phone_number"), "phone_number", @user.phone_number, placeholder: "+380501234567")
          render_field(t(".channels.telegram_chat_id"), "telegram_chat_id", @user.telegram_chat_id, placeholder: "123456789")
          render_field(t(".channels.push_token"), "push_token", @user.push_token, placeholder: t(".channels.push_placeholder"))

          div(class: "pt-4 border-t border-gaia-border") do
            button(type: "submit", class: "px-6 py-2 border border-gaia-primary-strong text-tiny uppercase tracking-widest text-gaia-primary-strong hover:bg-gaia-primary hover:text-gaia-primary-text transition-all") { t(".channels.save") }
          end
        end
      end
    end

    # [UI.3] Дві осі звʼязку, і друга тут не косметична. `for` ⟷ `id` (WCAG 1.3.1 —
    # без нього скрінрідер поля НЕ НАЗИВАЄ), плюс `aria-describedby` на підказку: вона
    # пояснює, ЧОМУ поле вимкнене або якого формату чекає, а лежачи окремим `<p>`
    # читається як не повʼязаний текст десь після поля — тобто саме тоді, коли вже
    # пізно. Обидва id з одного дому (`field_id_for`), щоб рукописних копій не було.
    def render_field(label_text, name, value, placeholder: nil, disabled: false, hint: nil)
      field_id = field_id_for(name)
      hint_id  = hint ? "#{field_id}_hint" : nil

      div(class: "space-y-2") do
        label(for: field_id, class: "text-mini text-gaia-text-muted uppercase tracking-widest block") { label_text }
        input(
          id: field_id,
          type: "text",
          name: name,
          value: value,
          placeholder: placeholder,
          disabled: disabled,
          aria_describedby: hint_id,
          class: tokens(
            "w-full bg-gaia-input-bg border border-gaia-input-border text-compact font-mono text-gaia-input-text px-4 py-3 focus-visible:border-gaia-primary-strong focus-visible:outline-none transition-colors",
            "opacity-50 cursor-not-allowed": disabled
          )
        )
        if hint
          p(id: hint_id, class: "text-mini text-gaia-text italic") { hint }
        end
      end
    end

    # [UI.10] Блок «типів сповіщень» знято (присуд власника 2026-08-14): пʼять
    # рядків малювались статичним переліком із безумовним «активно», тоді як
    # моделі преференцій не існує — ні таблиці, ні колонки, ні контролера.
    # Перемикач, якого не можна перемкнути, — не налаштування, а декорація, і
    # повернеться він разом із `NotificationPreference`, не раніше.
    def render_channels_status
      div(class: "p-6 border border-gaia-border bg-gaia-surface") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-6") { t(".active_channels.heading") }
        div(class: "space-y-4") do
          channel_status(t(".active_channels.email"), :email, @user.email_address)
          channel_status(t(".active_channels.sms"), :sms, @user.phone_number)
          channel_status(t(".active_channels.telegram"), :telegram, @user.telegram_chat_id)
          channel_status(t(".active_channels.push"), :push, @user.push_token)
        end
      end
    end

    # Станів ТРИ, і третій куплений: «немає транспорту» ⊥ «немає адреси». Доти
    # обидва згорталися в `not_configured`, тобто платформа приписувала людині
    # власну недоробку — вона вписала телефон, а екран казав «не налаштовано».
    def channel_status(label, channel, destination)
      div(class: "flex justify-between items-center py-2 border-b border-gaia-border") do
        span(class: "text-tiny text-gaia-text-subtle font-mono") { label }

        if !@available_channels.include?(channel)
          span(class: "text-mini text-gaia-text-subtle uppercase") { t(".active_channels.unavailable") }
        elsif destination.blank?
          span(class: "text-mini text-gaia-text-subtle uppercase") { t(".active_channels.not_configured") }
        else
          # [UI.17] Напис був «Connected», а гард — `destination.present?`, тобто
          # людина щось ВПИСАЛА в поле. Доставки ніхто не перевіряє: `phone_number`
          # має лише формат-валідацію E.164, `telegram_chat_id` і `push_token` —
          # жодної. Сусідня гілка вище вже каже `not_configured`, тож чесне слово
          # тут — «configured», і пара стає симетричною без нової механіки.
          # ⊕ Крапка перейшла на `-strong`: як сигнал вона підпадає під 1.4.11.
          div(class: "flex items-center gap-2") do
            div(class: "h-1.5 w-1.5 rounded-full bg-gaia-primary-strong")
            span(class: "text-mini text-gaia-primary-strong uppercase") { t(".active_channels.configured") }
          end
        end
      end
    end
  end
end
