# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Notifications
  class Settings < ApplicationComponent
    def initialize(user:)
      @user = user
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

    def render_channels_status
      div(class: "p-6 border border-emerald-900 bg-black") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-6") { t(".active_channels.heading") }
        div(class: "space-y-4") do
          channel_status(t(".active_channels.email"), @user.email_address.present?)
          channel_status(t(".active_channels.sms"), @user.phone_number.present?)
          channel_status(t(".active_channels.telegram"), @user.telegram_chat_id.present?)
          channel_status(t(".active_channels.push"), @user.push_token.present?)
        end
      end

      div(class: "p-6 border border-emerald-900 bg-emerald-950/5") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-4") { t(".notification_types.heading") }
        div(class: "space-y-3") do
          %i[critical_alerts warning_alerts minting_events slashing_events system_health].each do |key|
            div(class: "flex justify-between items-center") do
              span(class: "text-tiny text-gray-500 uppercase font-mono") { t(".notification_types.#{key}") }
              span(class: "text-mini text-emerald-500") { t(".notification_types.active") }
            end
          end
        end
      end
    end

    def channel_status(label, active)
      div(class: "flex justify-between items-center py-2 border-b border-emerald-900/20") do
        span(class: "text-tiny text-gray-400 font-mono") { label }
        if active
          div(class: "flex items-center gap-2") do
            div(class: "h-1.5 w-1.5 rounded-full bg-emerald-500 shadow-[0_0_6px_#10b981]")
            span(class: "text-mini text-emerald-500 uppercase") { t(".active_channels.connected") }
          end
        else
          span(class: "text-mini text-gray-700 uppercase") { t(".active_channels.not_configured") }
        end
      end
    end
  end
end
