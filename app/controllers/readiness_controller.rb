# frozen_string_literal: true

# [A3] Unauthenticated readiness probe for orchestrators (k8s / Akash / Kamal).
#
# Liveness ("is the process up?") is already served by Rails' `/up`
# (`rails/health#show`). This adds the missing READINESS signal ("can it serve
# traffic?"): it round-trips the hard dependencies (PostgreSQL + Redis/Upstash)
# and returns 503 when any is down, so the orchestrator stops routing to a node
# whose DB or Redis vanished instead of sending it doomed requests. The rich,
# admin-only `Api::V1::SystemHealthController` stays as the human dashboard.
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

  def database_ok?
    ActiveRecord::Base.connection.execute("SELECT 1")
    true
  rescue StandardError
    false
  end

  def redis_ok?
    Sidekiq.redis { |conn| conn.call("PING") } == "PONG"
  rescue StandardError
    false
  end
end
