# frozen_string_literal: true

class AlertMailer < ApplicationMailer
  def critical_notification
    @alert = params[:alert]
    @cluster = @alert.cluster
    @organization = @cluster.organization

    mail(
      to: @organization.billing_email,
      subject: "🚨 [S-NET] Критична тривога: #{@alert.alert_type.humanize} — #{@cluster.name}"
    )
  end
end
