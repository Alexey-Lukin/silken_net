# SPDX-License-Identifier: AGPL-3.0-or-later
class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"

  private

  # [I18N.1] Межа доставки — ЄДИНЕ місце, де локаль отримувача ще можна дізнатись.
  #
  # Обгортка стоїть саме тут, а не біля `deliver_later`: сам метод мейлера
  # виконується вже в Sidekiq, де немає ані запиту, ані `LocaleSettable`, тож
  # `I18n.locale` там дорівнює `default_locale` завжди. А `mail()` рендерить і
  # subject, і тіло синхронно всередині блоку — отже все, що треба перекласти,
  # потрапляє під нього.
  #
  # Джерело — persisted-колонка (`users.locale` / `organizations.locale`), бо
  # cookie переходу в чергу не переживає. NULL там означає «не обрано», і тоді
  # лист чесно йде базовою локаллю.
  def in_locale_of(record, &block)
    I18n.with_locale(supported_locale_for(record), &block)
  end

  # Fail-safe навмисно: значення в колонці могло пережити зняття локалі з
  # каталогу, а `I18n.with_locale` на невідомій локалі кидає `InvalidLocale`
  # (`enforce_available_locales` увімкнено). Лист не сміє загинути через мітку
  # мови — деградуємо до базової.
  def supported_locale_for(record)
    candidate = record.try(:locale).presence&.to_sym

    I18n.available_locales.include?(candidate) ? candidate : I18n.default_locale
  end
end
