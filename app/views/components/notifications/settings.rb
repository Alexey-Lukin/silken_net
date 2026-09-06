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

    # ⛔ `render_channels_form` ВИДАЛЕНО 2026-09-06 [ARCH.60, ⚖️ founder].
    #
    # Форма мала рівно ОДНЕ редаговане поле — `push_token`, — і транспорту для
    # нього не існує (`DeliveryChannels.available?(:push)` = жорсткий `false`).
    # Зняти саме поле означало б лишити форму з одним `disabled`-полем і кнопкою
    # «зберегти», що не зберігає нічого; зняти лише `permit` — дати тихий
    # `update({})` = true. Тому знято ПОВЕРХНЮ цілком: форма, екшен
    # `update_settings`, маршрут `PATCH`.
    #
    # ⊕ Що ЛИШИЛОСЬ і чому: `render_channels_status` читає стан і чесно друкує
    # «канал недоступний» — це свідчення, не збір. Колонка `users.push_token`
    # теж лишається: канал не відкинуто, а ⚖️-відкладено до мобільного клієнта
    # (ARCH.108). Підстава з боку GDPR — Art.5(1)(c) + Recital 39 («purposes
    # determined at the time of the collection»); повний розбір — шапка над
    # видаленим екшеном у `api/v1/notifications_controller.rb`.
    #
    # ⚠️ Урок UI.7, який тут стояв і який варто ПЕРЕНЕСТИ, а не втратити: цей
    # сайт був найнебезпечнішим кандидатом на `form_with(model:)` — поле є
    # колонкою `User`, тож скоуп виглядав би природно, а контролер читав params
    # ПЛОСКО. Під `user[...]` `permit` віддав би `{}`, `update({})` → **true**, і
    # людина побачила б «збережено» при нулі збережень. Дім правила — `04_04`.

    def render_channels_status
      div(class: "p-6 border border-gaia-border bg-gaia-surface") do
        h3(class: "text-tiny uppercase tracking-widest text-gaia-text-muted mb-6") { t(".active_channels.heading") }
        div(class: "space-y-4") do
          channel_status(t(".active_channels.email"), :email, @user.email_address)
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
          # людина щось ВПИСАЛА в поле. Доставки ніхто не перевіряє:
          # `push_token` —
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
