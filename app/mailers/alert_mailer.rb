# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class AlertMailer < ApplicationMailer
  def critical_notification
    @alert = params[:alert]
    @cluster = @alert.cluster
    @organization = @cluster.organization

    mail(
      to: @organization.billing_email,
      # Мітка типу — через TextFormatter, як в UI. Пошта поки рендериться в
      # `default_locale` (Sidekiq не має ні запиту, ні `LocaleSettable`), тож
      # видимого ефекту сьогодні нема — але `.humanize` віддавав би англійську
      # НАВІТЬ після того, як межа доставки навчиться ставити локаль отримувача.
      # Сам тіло листа лишається українським хардкодом → `00_07` I18N.1.
      subject: "🚨 [S-NET] Критична тривога: #{TreeChronicle::TextFormatter.alert_title(@alert)} — #{@cluster.name}"
    )
  end
end
