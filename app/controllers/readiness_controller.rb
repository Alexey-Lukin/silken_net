# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Unauthenticated readiness probe for orchestrators (Kamal proxy / k8s).
#
# Liveness ("is the process up?") is already served by Rails' `/up`
# (`rails/health#show`). This adds the missing READINESS signal ("can it serve
# traffic?"): it round-trips the hard dependencies (PostgreSQL + Redis/Upstash)
# and returns 503 when any is down, so the orchestrator stops routing to a node
# whose DB or Redis vanished instead of sending it doomed requests. The rich,
# admin-only `Api::V1::SystemHealthController` stays as the human dashboard.
#
# [ARCH.81] Both surfaces now share `SilkenNet::HealthProbes`. They used to hold
# private copies, and the copies diverged: this one round-tripped, the dashboard
# asked objects about themselves — i.e. the machine got the truth and the human
# got a guess. A probe belongs to one home precisely because two of them drift.
#
# Inherits `ActionController::Base` directly (like `Rails::HealthController`) to
# stay outside any `ApplicationController` auth/CSRF chain. `/ready` is exempt
# from the Rack::Attack global throttle (see `config/initializers/rack_attack.rb`).
class ReadinessController < ActionController::Base
  def show
    checks = { database: database_ok?, redis: redis_ok? }
    ready  = checks.values.all?

    render json: { status: ready ? "ready" : "not_ready", checks: checks },
           status: ready ? :ok : :service_unavailable
  end

  private

  # Primary connection. cache/queue/cable share host+credentials with primary
  # (config/database.yml component style), so a reachable primary is a strong proxy
  # for the whole Cloud SQL instance; per-DB probing is omitted to keep /ready fast
  # and non-flaky.
  def database_ok?
    SilkenNet::HealthProbes.database_reachable?
  end

  # Both Redis CLIENTS — Sidekiq queues and Kredis (Web3 nonce + mint/burn locks).
  # Not two databases: Upstash exposes one, so both share a keyspace [INF.22]; the
  # probe still checks both because they are separate clients with separate pools,
  # and a live Sidekiq pool proves nothing about the Kredis one. /ready must 503 if
  # either is unreachable, so the orchestrator stops routing to a node that cannot
  # safely mint/burn.
  def redis_ok?
    SilkenNet::HealthProbes.redis_reachable?
  end
end
