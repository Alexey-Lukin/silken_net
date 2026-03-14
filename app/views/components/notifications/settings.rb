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
          h3(class: "text-tiny uppercase tracking-[0.4em] text-emerald-700") { "🔔 Neural Web — Notification Channels" }
          p(class: "text-xs text-gray-600 mt-1") { "Налаштування каналів зв'язку: куди надсилати сповіщення про тривоги та події." }
        end
      end
    end

    def render_channels_form
      div(class: "p-6 border border-emerald-900 bg-black") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-6") { "Channel Configuration" }

        form(action: api_v1_notifications_settings_path, method: "post", class: "space-y-6") do
          input(type: "hidden", name: "_method", value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          render_field("Email Address", "email", @user.email_address, disabled: true, hint: "Змінити email можна в профілі.")
          render_field("Phone Number (E.164)", "phone_number", @user.phone_number, placeholder: "+380501234567")
          render_field("Telegram Chat ID", "telegram_chat_id", @user.telegram_chat_id, placeholder: "123456789")
          render_field("Push Token", "push_token", @user.push_token, placeholder: "FCM or APNs token")

          div(class: "pt-4 border-t border-emerald-900/30") do
            button(type: "submit", class: "px-6 py-2 border border-emerald-500 text-tiny uppercase tracking-widest text-emerald-500 hover:bg-emerald-500 hover:text-black transition-all") { "Save Channels →" }
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
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-6") { "Active Channels" }
        div(class: "space-y-4") do
          channel_status("📧 Email", @user.email_address.present?)
          channel_status("📱 SMS / Phone", @user.phone_number.present?)
          channel_status("✈️ Telegram", @user.telegram_chat_id.present?)
          channel_status("🔔 Push", @user.push_token.present?)
        end
      end

      div(class: "p-6 border border-emerald-900 bg-emerald-950/5") do
        h3(class: "text-tiny uppercase tracking-widest text-emerald-700 mb-4") { "Notification Types" }
        div(class: "space-y-3") do
          %w[Critical\ Alerts Warning\ Alerts Minting\ Events Slashing\ Events System\ Health].each do |event|
            div(class: "flex justify-between items-center") do
              span(class: "text-tiny text-gray-500 uppercase font-mono") { event }
              span(class: "text-mini text-emerald-500") { "ACTIVE" }
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
            span(class: "text-mini text-emerald-500 uppercase") { "Connected" }
          end
        else
          span(class: "text-mini text-gray-700 uppercase") { "Not configured" }
        end
      end
    end
  end
end
