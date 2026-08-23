# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class AlertMailer < ApplicationMailer
  # [ARCH.60 ⚖️ 2026-08-23] Лист про critical-тривогу їде ТІЄЮ Ж чергою, що й
  # рішення його надіслати. Доти `deliver_later_queue_name` не був заданий ніде,
  # тож `MailDeliveryJob` брав `ActiveJob::Base.default_queue_name` → `default`(5)
  # — тобто ланцюг ламався на останньому кроці: `AlertNotificationWorker` судить
  # про критичність у черзі `alerts`(2), фан-аут Telegram їде `alerts`(2), а
  # ЄДИНИЙ формальний лист падав за `downlink`(4), тобто за чанками OTA-кампанії.
  # Обсяг тут менший за сусідів по черзі — одна відправка на алерт (не N на
  # стейкхолдерів), тож підняття не тисне на `critical`(3)-слешинг.
  # ⚠️ Пер-мейлерне СВІДОМО: `PasswordMailer` лишається на `default` — це UX, не
  # безпека, і піднімати його над слешингом не можна. Носій обох половин —
  # `spec/quality/activejob_queue_declaration_spec.rb`.
  self.deliver_later_queue_name = :alerts

  def critical_notification
    @alert = params[:alert]
    @cluster = @alert.cluster
    @organization = @cluster.organization

    # [I18N.1] Локаль ОРГАНІЗАЦІЇ, не користувача: лист іде на `billing_email`,
    # за яким може не стояти жоден User-запис. Усередині блоку локалізується все —
    # включно з `alert_title` і `@alert.message`, які самі резолвляться через
    # `I18n.t` у момент читання (раніше вони мовчки виходили англійськими
    # всередині українського тіла).
    in_locale_of(@organization) do
      mail(
        to: @organization.billing_email,
        subject: default_i18n_subject(
          type: TreeChronicle::TextFormatter.alert_title(@alert),
          cluster: @cluster.name
        )
      )
    end
  end
end
