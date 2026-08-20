# SPDX-License-Identifier: AGPL-3.0-or-later
class ApplicationMailer < ActionMailer::Base
  # [ARCH.60] Відправник приходить із ENV `MAIL_FROM`; дім резолву — там же, де
  # сентинел «не налаштовано» і предикат, що його читає.
  default from: Notifications::DeliveryChannels.configured_sender
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

  # Резолв виїхав у спільний дім, коли Telegram став другим каналом із тією
  # самою потребою (fail-safe-семантика — у коментарі модуля).
  def supported_locale_for(record)
    Notifications::RecipientLocale.for(record)
  end
end
