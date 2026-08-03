# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Views
  module Shared
    module UI
      # [SEC.25] Зведення помилок валідації для форми, що перемалювалась на 422.
      #
      # 🔴 Це ТРЕТІЙ жанр повідомлення в дереві, і плутати їх не можна в жоден бік:
      #   * `FlashMessages` — те, що ПЕРЕЖИЛО редирект (дію завершено, сторінка інша);
      #   * `flash_alert:`/`password_error:` в auth-компонентах — ОДНА помилка
      #     поточного сабміту, коли причина одна й наперед відома (пароль не збігся);
      #   * цей компонент — СПИСОК причин, яких контролер наперед не знає, бо їх
      #     віддає модель (`full_messages`), і людина лишається у формі, щоб їх
      #     виправити.
      #
      # ⚠️ Рендер УМОВНИЙ (порожній список не малює нічого) — і це свідома відмінність
      # від `FlashMessages`, чиї регіони стоять у DOM завжди. Там порожня коробка
      # потрібна, бо вузол мусить ПЕРЕЖИТИ morph, аби скрінрідер помітив зміну
      # всередині. Тут же відповідь на 422 — повний рендер сторінки: вузол приходить
      # НОВИМ разом зі своїм текстом, а `role="alert"` AT озвучує саме в цьому
      # випадку (на відміну від `role="status"`). Тобто порожня коробка тут не додала
      # б чутності — лише порожню рамку на кожній чистій формі.
      #
      # 🔴 Заголовок — ПАРАМЕТР, і це вимір, а не гнучкість про запас. Три реалізації,
      # які цей компонент замінив, мали три ключі, але лише ДВА з них казали одне
      # («Validation Failed» ⟷ «Validation Errors»). Третій — `provisioning.new
      # .errors_title` = «Ініціалізація не вдалася» — називає інший АКТ: там
      # більшість причин узагалі не з AR-валідації, а з guard-клауз контролера
      # (зайнятий UID → 409, чужий кластер → 404), які лише кладуться в `errors`,
      # щоб доїхати сюди. Звести його до «перевірку не пройдено» означало б
      # переназвати лісникові подію, яка з ним сталась.
      class ErrorSummary < ApplicationComponent
        # @param messages [Array<String>] зазвичай `record.errors.full_messages`.
        #   Свідомо НЕ сам `errors`-об'єкт: компонент не має причини знати про
        #   ActiveModel, а спека тоді не потребує ані фікстури моделі, ані `double`
        #   з двома методами — рівно та вигадана фікстура, що вже двічі цементувала
        #   тут неіснуючий контракт (`04_06 §B.2` BP #14).
        # @param title [String, nil] заголовок; nil → спільний «перевірку не пройдено».
        def initialize(messages:, title: nil)
          @messages = Array(messages).compact_blank
          @title    = title
        end

        def view_template
          return if @messages.empty?

          div(
            # Тон позичений СВІДОМО: «як виглядає помилка» — властивість дизайн-
            # системи, не жанру, тож два жанри мусять малювати її однаково, і
            # другий дім тут дав би дві правди про один факт. `fetch` fail-loud:
            # перейменований тон впаде одразу на спеці, а не тихо змінить колір.
            class: tokens(
              "p-4 border text-xs font-mono",
              Views::Shared::UI::FlashMessages::TONES.fetch("error")
            ),
            role: "alert"
          ) do
            p(class: "uppercase tracking-widest") { @title.presence || default_title }
            ul(class: "list-disc ml-4 mt-2") do
              @messages.each { |message| li { message } }
            end
          end
        end

        private

        # Абсолютний ключ, а не `t(".title")`: автоскоуп дав би
        # `views.shared.ui.error_summary.*`, тоді як shared-компоненти цього дерева
        # локалізуються під `ui.*` (див. `Skeleton`). Але заводити навіть `ui.…` тут
        # не треба — `errors.api.validation_failed_title` уже написаний у всіх
        # чотирьох локалях і вже вживався найздоровішою з трьох реалізацій.
        def default_title
          I18n.t("errors.api.validation_failed_title")
        end
      end
    end
  end
end
