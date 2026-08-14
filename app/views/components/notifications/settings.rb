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
      div(class: "space-y-8 animate-in fade-in duration-500") do
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
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { t(".heading") }
          p(class: "text-xs text-gray-600 mt-1") { t(".subtitle") }
        end
      end
    end

    def render_channels_form
      div(class: "p-6 border border-emerald-900 bg-black") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-6") { t(".channels.heading") }

        form(action: notifications_settings_path, method: "post", class: "space-y-6") do
          input(type: "hidden", name: "_method", value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          # [SEC.25] Дзеркало `settings#update`: телефон не в E.164 дає 422, і доти
          # сторінка просто перемальовувалась із тим самим значенням у полі.
          render Views::Shared::UI::ErrorSummary.new(messages: @user.errors.full_messages)

          render_field(t(".channels.email_address"), "email", @user.email_address, disabled: true, hint: t(".email_hint"))
          render_field(t(".channels.phone_number"), "phone_number", @user.phone_number, placeholder: "+380501234567")
          render_field(t(".channels.telegram_chat_id"), "telegram_chat_id", @user.telegram_chat_id, placeholder: "123456789")
          render_field(t(".channels.push_token"), "push_token", @user.push_token, placeholder: t(".channels.push_placeholder"))

          div(class: "pt-4 border-t border-emerald-900/30") do
            button(type: "submit", class: "px-6 py-2 border border-emerald-500 text-tiny uppercase tracking-widest text-emerald-500 hover:bg-emerald-500 hover:text-black transition-all") { t(".channels.save") }
          end
        end
      end
    end

    def render_field(label, name, value, placeholder: nil, disabled: false, hint: nil)
      div(class: "space-y-2") do
        label(class: "text-mini text-gray-600 uppercase tracking-widest block") { label }
        input(
          type: "text",
          name: name,
          value: value,
          placeholder: placeholder,
          disabled: disabled,
          class: tokens(
            "w-full bg-zinc-950 border border-emerald-900/50 text-compact font-mono text-emerald-400 px-4 py-3 focus-visible:border-emerald-500 focus-visible:outline-none transition-colors",
            "opacity-50 cursor-not-allowed": disabled
          )
        )
        if hint
          p(class: "text-mini text-gray-700 italic") { hint }
        end
      end
    end

    # [UI.10] Блок «типів сповіщень» знято (присуд власника 2026-08-14): пʼять
    # рядків малювались статичним переліком із безумовним «активно», тоді як
    # моделі преференцій не існує — ні таблиці, ні колонки, ні контролера.
    # Перемикач, якого не можна перемкнути, — не налаштування, а декорація, і
    # повернеться він разом із `NotificationPreference`, не раніше.
    def render_channels_status
      div(class: "p-6 border border-emerald-900 bg-black") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-6") { t(".active_channels.heading") }
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
      div(class: "flex justify-between items-center py-2 border-b border-emerald-900/20") do
        span(class: "text-tiny text-gray-400 font-mono") { label }

        if !@available_channels.include?(channel)
          span(class: "text-mini text-gray-700 uppercase") { t(".active_channels.unavailable") }
        elsif destination.blank?
          span(class: "text-mini text-gray-700 uppercase") { t(".active_channels.not_configured") }
        else
          div(class: "flex items-center gap-2") do
            div(class: "h-1.5 w-1.5 rounded-full bg-emerald-500 shadow-[0_0_6px_#10b981]")
            span(class: "text-mini text-emerald-500 uppercase") { t(".active_channels.connected") }
          end
        end
      end
    end
  end
end
