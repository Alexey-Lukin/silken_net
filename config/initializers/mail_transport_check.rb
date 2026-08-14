# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [ARCH.60] Refuse to boot production without a mail transport.
#
# WHY a boot refusal and not a warning. Until now an unconfigured deploy failed
# in the quietest way available: `deliver_later` enqueued fine, the controller
# returned 200, and the Sidekiq job hit `localhost:25`, retried 25 times over
# ~three weeks and died in the dead set. Password reset was dead end-to-end and
# a critical wildfire alert reached nobody — with no signal on any surface.
#
# A `Rails.logger.warn` would have been the fourth self-attesting line in this
# exact tract; ARCH.78 had just finished removing three of them. A log entry
# nobody reads is what created this class of defect, so the signal has to be one
# that cannot be scrolled past.
#
# The judgement itself is NOT duplicated here: it asks
# `Notifications::DeliveryChannels.available?(:email)` — the same predicate the
# settings screen renders. Two answers to "is email alive?" is precisely the
# drift that would let the platform boot believing the channel works while
# drawing it as dead. Content-judge unit-tested in that module's spec; this file
# only decides WHEN to enforce and how to bypass — mirroring
# `active_record_encryption_keys_check.rb`.
#
# Process scope: web AND job, skipping only the CoAP daemon. Sidekiq is what actually
# delivers (deliver_later), but web is gated too — it is the surface an operator looks
# at, so gating only the deliverer would hide the misconfiguration behind a healthy
# dashboard. The coap listener is excluded because no path leads from it to a mailer.

Rails.application.config.after_initialize do
  # Canopy shares RAILS_ENV=production with mainnet; both are gated here.
  next unless Rails.env.production?

  # The Dockerfile boots production for `assets:precompile` with no secrets on
  # purpose; the runtime boot (no dummy flag) still enforces this.
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?

  # The CoAP intake daemon loads the full environment (every initializer runs here)
  # but is pure UDP glue — it parses datagrams and perform_async's them, and there is
  # no path from it to a mailer. Demanding a transport would block the telemetry
  # intake over a capability the process does not have. Mirrors
  # master_key_strength_check.rb, which skips the same process for the same reason.
  next if $PROGRAM_NAME.include?("coap_listener")

  if ENV["SILKENNET_SKIP_MAIL_TRANSPORT_CHECK"] == "1"
    # Loud on purpose — a deployment that deliberately ships without email must
    # leave a trail, so the escape hatch cannot quietly become the norm.
    Rails.logger.warn(
      "[ARCH.60] Mail-transport check BYPASSED via SILKENNET_SKIP_MAIL_TRANSPORT_CHECK=1 — " \
      "password reset and critical-alert email are DEAD on this deploy. Unset it once " \
      "SMTP is provisioned."
    )
    next
  end

  next if Notifications::DeliveryChannels.available?(:email)

  # The message names what was OBSERVED, not a guessed cause: "unset" and "set to the
  # REQUIRED_SECRET_NOT_SET placeholder" are different operator actions, and telling a
  # deployer their variable is missing when it is actually present-but-unusable sends
  # them to the wrong file. Neither value is a secret (both live in env.clear), so both
  # are echoed.
  channels = Notifications::DeliveryChannels
  gaps = []

  unless channels.sender_configured?
    sender = ApplicationMailer.default[:from].to_s
    gaps <<
      if sender == channels::SCAFFOLD_SENDER
        "#{channels::SENDER_ENV} is unset — the sender is still the Rails scaffold " \
          "address (#{sender}), which no recipient will accept."
      else
        "#{channels::SENDER_ENV}=#{sender.inspect} is not an email address (a deploy " \
          "placeholder or a mispaste reaches here looking set)."
      end
  end

  unless channels.smtp_host_configured?
    host = ActionMailer::Base.smtp_settings[:address].to_s
    gaps <<
      if host.blank? || host == channels::UNCONFIGURED_SMTP_HOST
        "SMTP_ADDRESS is unset — outgoing mail would go to the local machine and be refused."
      else
        "SMTP_ADDRESS=#{host.inspect} is not a hostname (a deploy placeholder or a " \
          "mispaste reaches here looking set)."
      end
  end

  raise "[ARCH.60] Refusing to boot (RAILS_ENV=#{Rails.env}) — no mail transport:\n  " +
        gaps.join("\n  ") +
        "\nSet MAIL_FROM + SMTP_ADDRESS on web + job (credentials SMTP_USER_NAME/SMTP_PASSWORD " \
        "as your ESP requires; see docs/06_04 §2.1 and docs/00_07 ARCH.60). Without them " \
        "password reset and critical-alert email do not work at all. To ship deliberately " \
        "without email, set SILKENNET_SKIP_MAIL_TRANSPORT_CHECK=1."
end
