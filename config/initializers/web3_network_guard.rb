# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Refuse to boot a strict deployment with unsafe Web3 wiring: an RPC URL on the wrong
# chain family (mainnet value minted on a throwaway chain, or staging able to sign real
# transactions), a missing/malformed oracle signer key (KeyError → silent Sidekiq
# DeadSet), or a broken DAO-treasury address (its read-sites rescue everything → the 2%
# Dynamic Tax silently stays off). The content judgement lives in
# `Security::Web3NetworkGuard` (unit-tested); this initializer only decides WHEN to
# enforce + how to bypass — mirroring `config/initializers/master_key_strength_check.rb`.
#
# 🔑 Two axes, deliberately NOT merged [OPS.37]. This gate is the "hardened runtime" half
# and stays keyed on `Rails.env.production? ∨ WEB3_STRICT_MODE` — a staging slot wants it
# ON. Which chain the slot may touch is the OTHER half, declared per slot in
# `WEB3_CHAIN_ENV` and judged inside the guard. Reading `Rails.env` as an answer to the
# second question is the conflation this split exists to remove.

Rails.application.config.after_initialize do
  # Enforce in production/canopy, or anywhere WEB3_STRICT_MODE=true (the same
  # gate IoTeX / Hadron fail-closed under).
  next unless Rails.env.production? || ENV["WEB3_STRICT_MODE"] == "true"

  # Dockerfile `assets:precompile` boots production with no secrets on purpose;
  # the runtime boot (no dummy flag) still enforces this.
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?

  if ENV["SILKENNET_SKIP_WEB3_NETWORK_GUARD"] == "1"
    # Loud on purpose — a bypassed boot-time safety check must leave a trail so
    # the rescue-boot escape hatch cannot quietly become routine.
    Rails.logger.warn(
      "Web3 network guard BYPASSED via SILKENNET_SKIP_WEB3_NETWORK_GUARD=1 — " \
      "intended only for a one-off rescue boot. Unset it for normal operation."
    )
    next
  end

  # Key-PRESENCE is demanded only where keys are consumed: the Sidekiq signer
  # process. The web/coap containers boot keyless by design (plaintext-ENV
  # exposure) — a missing key still fails loudly, at job-boot, before any DeadSet.
  #
  # 🔑 But "where it is consumed" has THREE answers, not two, and only the guard can
  # hold that per-variable: job (Sidekiq) · web (Puma, and any rake task in that
  # container — `db:prepare` boots this same code) · coap. The `coap_listener`
  # exemption uses the $PROGRAM_NAME idiom `master_key_strength_check.rb` already
  # relies on, and it is load-bearing: that process loads every initializer while its
  # `/etc/silkennet/coap.env` carries no contract address — an OBSERVATION about the
  # seed heredoc in `terraform/compute.tf`, NOT a canonized invariant and NOT gated.
  # ⛔ `06_04 §5.7` is the secrets-at-rest latch and says nothing about addresses; that
  # false citation stood on five surfaces until 2026-09-01. Full note: the guard's header.
  # ⚠️ VERIFIED, not assumed (2026-09-01) — INF.17 records that the coap daemon's boot was
  # never proven by a live run, so the idiom it depends on was an inherited assumption, and
  # getting it wrong here refuses the telemetry intake's boot. Measured: ALL THREE launch
  # sites — `config/deploy.yml` role cmd · the anchor systemd unit in `terraform/compute.tf` ·
  # `Procfile.dev` — are `bundle exec ruby lib/daemons/coap_listener`, that form yields
  # `$PROGRAM_NAME == "lib/daemons/coap_listener"`, and the daemon reassigns neither `$0`
  # nor the proctitle — while its line 5 IS `require_relative "../../config/environment"`.
  # ⚠️ This said "both launch sites" for hours and missed `Procfile.dev` — an inventory
  # presented as a MEASUREMENT while short by a third, in the very comment whose stated
  # ground is that the measurement was done. No consequence (dev has the guard off), but
  # the shape is the one this whole pass was hunting.
  # ⛔ Change ANY launch form and re-measure: the failure would be a silent non-boot of
  # the one process the forest speaks through.
  signer_process = Sidekiq.server?
  coap_process   = $PROGRAM_NAME.include?("coap_listener")
  web_process    = !signer_process && !coap_process

  violations = Security::Web3NetworkGuard.violations(
    ENV, signer_process: signer_process, web_process: web_process
  )
  next if violations.empty?

  # All five are echoed because they are the FIVE separate questions this boot asks: which
  # SLOT, which runtime, which enforcement arm armed the guard, which chain family this
  # slot claims, and which PROCESS CLASS refused. A `[chain]` violation is unreadable
  # without the fourth — it is half the assertion. ⚠️ The slot was the one MISSING when
  # this comment said "three" [INF.27]: both deploys carry RAILS_ENV=production, so a
  # canopy boot-refusal and a production one were indistinguishable in the log stream —
  # precisely when telling them apart matters most. ⊕ The process class joined for the
  # same reason on 2026-09-01: presence is now scoped per-variable across three process
  # classes, so `[address] … is not set` cannot be acted on without knowing which
  # container said it — the operator's next move differs per class.
  process_class = if signer_process then "job"
  elsif coap_process then "coap"
  else "web"
  end

  raise SecurityError,
        "Refusing to boot (slot=#{SilkenNet::DeploymentSlot.current}, " \
        "process=#{process_class}, " \
        "RAILS_ENV=#{Rails.env}, " \
        "WEB3_STRICT_MODE=#{ENV['WEB3_STRICT_MODE'].inspect}, " \
        "#{Security::Web3NetworkGuard::CHAIN_ENV_VAR}=" \
        "#{Security::Web3NetworkGuard.chain_env(ENV).inspect}):\n  " +
        violations.join("\n  ") +
        "\nSee docs/06_04 (Web3 deploy secrets). For a deliberate rescue boot, " \
        "set SILKENNET_SKIP_WEB3_NETWORK_GUARD=1."
end
