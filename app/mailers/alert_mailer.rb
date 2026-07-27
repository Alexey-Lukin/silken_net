# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class AlertMailer < ApplicationMailer
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
