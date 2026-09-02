# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# =============================================================================
# 🎰 DEPLOYMENT SLOT — "which deploy am I", NOT "which Rails env am I"
# =============================================================================
# [INF.27] Both slots run `RAILS_ENV=production`, and canopy does so ON PURPOSE:
# it wants the hardened runtime (`WEB3_STRICT_MODE`, fail-closed guards, no
# stubs). So `Rails.env` cannot answer "which deploy is this" — it answers
# "production" on both — and every surface that NAMES, NAMESPACES or TAGS a
# shared external resource with `Rails.env` stamps the same string twice.
#
# 🔴 The failure mode is a WRONG label, not a missing one, and that is strictly
# worse: an empty field is visible, a wrong one is not. `config/deploy.canopy.yml`
# already makes exactly this argument for the Alloy `slot` label — this file is
# that argument applied to the Rails roles, which it had not reached.
#
# 🏠 ONE HOME, and it is the ENV VAR, not this file. `DEPLOYMENT_SLOT` was born
# for the observability accessory (`config/deploy.yml` + `config/deploy.canopy.yml`
# → `deploy/alloy/config.alloy` `slot = coalesce(sys.env("DEPLOYMENT_SLOT"), …)`).
# This module exists only so the FALLBACK RULE has a single definition instead of
# one copy per reader — there are six readers, and six copies of a `||` expression
# is a drift surface, not a convention.
#
# 🔑 The fallback is `Rails.env`, NOT the literal "production", and the choice is
# load-bearing in both directions:
#   · dev/test must keep reporting `development` / `test` — a literal "production"
#     default would file every local exception into the production Sentry project;
#   · every DEPLOYED surface already has `RAILS_ENV=production` (the image default,
#     `Dockerfile`), so an undeclared slot lands on `production` there — i.e. the
#     same value it had before this split. A forgotten flag can only fail to
#     DISCRIMINATE; it can never point canopy's data at something new.
#
# ⛔ Read it through here, never as `ENV.fetch("DEPLOYMENT_SLOT")` without a
# default. Two reasons, and the second is the one that bites: (1) the CoAP anchor
# runs from a systemd env-file (`terraform/compute.tf`) that carries it only since
# 2026-09-02 (OPS.37 — line 1 of the intake slot switch) and is created ONCE, so an
# anchor filled before that lives without the line and a bare fetch is a KeyError
# at boot there; (2) the INF.12 declaration gate
# (`spec/deploy/env_fetch_declaration_spec.rb`) reads `config/deploy.yml` and —
# until it was hardened alongside this change — could not tell a var declared for
# a Rails ROLE from one declared for an ACCESSORY, so a bare fetch would have
# passed GREEN while the var reached only the Alloy container.
#
# Required explicitly from `config/application.rb` (NOT autoloaded): the earliest
# readers are `config/cache.yml` and `config/storage.yml`, whose ERB is evaluated
# during framework initializers — earlier than it is safe to lean on Zeitwerk.
module SilkenNet
  module DeploymentSlot
    module_function

    # @return [String] "production" · "canopy" · "development" · "test"
    def current
      ENV["DEPLOYMENT_SLOT"].presence&.strip || Rails.env.to_s
    end
  end
end
