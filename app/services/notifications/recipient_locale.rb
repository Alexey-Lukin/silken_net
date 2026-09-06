# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Notifications
  # [I18N.1] Локаль ОТРИМУВАЧА на межі доставки — один дім для всіх каналів,
  # що рендерять текст у Sidekiq (сьогодні — сама пошта; ⚫ Telegram знято 2026-09-06): там немає ані запиту, ані
  # `LocaleSettable`, тож `I18n.locale` завжди дорівнює базовій.
  #
  # Fail-safe навмисно: значення в persisted-колонці могло пережити зняття
  # локалі з каталогу, а `I18n.with_locale` на невідомій кидає `InvalidLocale`
  # (`enforce_available_locales` увімкнено). Сповіщення не сміє загинути через
  # мітку мови — деградуємо до базової. NULL означає «не обрано» — теж базова.
  module RecipientLocale
    module_function

    # @param record [#locale, nil] отримувач (`User` / `Organization`)
    # @return [Symbol] локаль із каталогу, придатна для `I18n.with_locale`
    def for(record)
      candidate = record.try(:locale).presence&.to_sym

      I18n.available_locales.include?(candidate) ? candidate : I18n.default_locale
    end
  end
end
