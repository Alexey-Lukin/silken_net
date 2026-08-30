# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Enterprise-grade Sidekiq configuration with Redis connection pooling and
# network timeouts.
#
# 🔴 KEYSPACE, not numbered databases [INF.22]. This header used to declare a
# "DB ISOLATION STRATEGY" — Sidekiq on DB 0, Kredis on DB 1, Rack::Attack on
# DB 2 — and that isolation cannot exist on Upstash, which exposes exactly one
# logical database (`SELECT 1` → `ERR Only 0th database is supported!`, measured
# against our own instance 2026-08-30). All three now share one keyspace and are
# kept apart by key prefixes; Sidekiq is the one that carries none, because
# Sidekiq 7+ raises on `namespace:` and its keys (`queue:`, `retry`, `dead`,
# `stat:`, `processes`) collide with nothing. See `config/initializers/kredis.rb`
# for the namespace, and `config/redis/shared.yml` for what the split protected
# and how that ground is served now.

SIDEKIQ_REDIS_URL = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

# `.presence`, не `fetch`-дефолт: присутня-порожня змінна віддає "", і `"".to_i`
# дало б нуль — тобто таймаут без межі та пул нульового розміру.
SIDEKIQ_REDIS_TIMEOUT = (ENV["SIDEKIQ_REDIS_TIMEOUT"].presence || 5).to_i

# ⛔ `size:` тут СВІДОМО відсутній [ARCH.59]: Sidekiq 7+ тримає ДВА пули й виводить
# обидва сам — капсульний із `:concurrency` (`config/sidekiq.yml`) та окремий
# internal під heartbeat / sidekiq-scheduler / Web UI. Явний `size:` іде через
# `.merge(@redis_config)`, тобто перекривав ОБИДВА: прибивав капсульний до
# константи незалежно від `:concurrency` (крок 3 DOC-R.10 розщеплює процеси
# per-queue — там розходження стає живим) і роздував internal. Розбір — дім
# `04_02 §11` DOC-R.10.
SIDEKIQ_REDIS_OPTIONS = {
  url: SIDEKIQ_REDIS_URL,
  network_timeout: SIDEKIQ_REDIS_TIMEOUT,
  pool_timeout: SIDEKIQ_REDIS_TIMEOUT
}.freeze

# Клієнтський процес капсул не має, тож вивести стелю Sidekiq'у нізвідки — її
# задають треди, що кличуть `perform_async`, плюс запас на Sidekiq::Web. Дзеркалить
# `config/database.yml`, але БЕЗ `PUMA_MAX_IO_THREADS`: io-позначених шляхів нуль
# [ARCH.80], а Redis у нас managed (Upstash), тож стеля з'єднань не безкоштовна.
SIDEKIQ_CLIENT_POOL_SIZE = (
  ENV["SIDEKIQ_CLIENT_POOL_SIZE"].presence || (ENV["RAILS_MAX_THREADS"].presence || 3).to_i + 2
).to_i

Sidekiq.configure_server do |config|
  config.redis = SIDEKIQ_REDIS_OPTIONS

  # [INF.14 / 06_03 §2.9] Job-контейнер віддає власний /metrics: реєстр
  # Prometheus — in-process, тож money-path/telemetry-лічильники воркерів
  # web:80 фізично не бачить. Alloy скрейпить job:9394 другим таргетом.
  config.on(:startup) do
    SilkenNet::MetricsExporter.start(port: ENV.fetch("METRICS_PORT", 9394).to_i)
  end
end

Sidekiq.configure_client do |config|
  config.redis = SIDEKIQ_REDIS_OPTIONS.merge(size: SIDEKIQ_CLIENT_POOL_SIZE)
end
