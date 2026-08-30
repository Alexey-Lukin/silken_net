# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "puma/server"

module SilkenNet
  # Embedded /metrics-експортер для процесів без власного HTTP-сервера
  # (Sidekiq job-контейнер, CoAP-демон). Реєстр Prometheus — in-process:
  # інкременти воркерів web:80 фізично не бачить, тож кожен процес віддає
  # свій зріз сам, а Alloy скрейпить три process-таргети по стабільних
  # DNS-аліасах ролей у спільній docker-мережі `kamal` (silken-web:80 /
  # silken-job:9394 / silken-coap:9395 — deploy/alloy/config.alloy,
  # канон 06_03 §2.9; ⚖️ OPS.37 2026-08-30).
  #
  # Реюзає PrometheusCollector (IP-allowlist + Basic Auth + gauge-refresh)
  # як Rack-app із 404-fallback — та сама security-поверхня, що на web.
  # Порт НЕ публікується на хост узагалі (`options.publish` виміряно й
  # відхилено — ламав роллінг, відкочено 2026-08-29): скрейп іде
  # контейнер-до-контейнера в межах docker-мережі, назовні — ніколи.
  #
  # Збій експортера НЕ вбиває основний процес: метрики — не money-path;
  # гучний лог + Sentry, процес живе без /metrics.
  module MetricsExporter
    NOT_FOUND = ->(_env) { [ 404, { "content-type" => "text/plain" }, [ "Not Found" ] ] }

    # Scrape раз на 15с — одного треда досить; без queue-backlog'а.
    PUMA_OPTIONS = { min_threads: 0, max_threads: 1 }.freeze

    module_function

    # Повертає Puma::Server (фоновий тред) або nil при збої бінда.
    # Puma::Server — внутрішній клас гема (пінований 8.x): API-дрейф ловить
    # spec/lib/silken_net/metrics_exporter_spec.rb реальним HTTP-запитом.
    def start(port:, host: "0.0.0.0")
      server = Puma::Server.new(PrometheusCollector.new(NOT_FOUND), nil, PUMA_OPTIONS)
      server.add_tcp_listener(host, port)
      server.run
      Rails.logger.info "📊 [MetricsExporter] /metrics відкрито на #{host}:#{port}"
      server
    rescue SystemCallError, RuntimeError => e
      Rails.logger.error "📊 [MetricsExporter] не стартував (#{e.class}: #{e.message}) — " \
                         "процес продовжує без /metrics"
      Sentry.capture_exception(e) if defined?(Sentry)
      nil
    end
  end
end
