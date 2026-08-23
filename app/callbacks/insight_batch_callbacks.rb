# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🧠 INSIGHT BATCH CALLBACKS (Sidekiq Pro Batch Orchestration)
# = ===================================================================
# [A-3: Wiki 04_02 §11 — Sidekiq Batch для покластерної обробки]
#
# Колбеки, що спрацьовують після завершення батчу GenerateClusterInsightWorker.
#
# Sidekiq Pro гарантує:
# - on_success: спрацює ТІЛЬКИ якщо ВСІ джоби батчу виконані успішно
# - on_complete: спрацює коли всі джоби завершились (включаючи failed)
#
# Цей колбек:
# 1. Запускає ClusterHealthCheckWorker для аудиту NaaS-контрактів
# 2. [INS.1] Fan-out страхового оракула за kill-switch-прапором
#
# ⛔ Тут доти стояв третій пункт — «Очищує старі TelemetryLog записи (>7 днів)».
# Механізм знято ⚖️ 2026-08-21: рядкове видалення телеметрії заборонене, єдиний
# легітимний ретеншн — дроп партицій ([ARCH.70]). Коментар пережив свій код на
# два дні; носій `spec/quality/telemetry_retention_home_spec.rb` цього не ловить
# за побудовою — він сканує `delete_all`, а не прозу.
class InsightBatchCallbacks
  # Спрацьовує коли ВСІ GenerateClusterInsightWorker джоби успішно завершились.
  # Гарантує, що аудит контрактів запускається тільки після повної агрегації.
  #
  # @param status [Sidekiq::Batch::Status] статус батчу (bid, total, failures)
  # @param options [Hash] параметри, передані при реєстрації колбека
  def on_success(status, options)
    date_string = options["date"]

    Rails.logger.info "✅ [Insight Batch] Батч #{status.bid} завершено успішно. " \
                      "Дата: #{date_string}. Запуск аудиту контрактів..."

    # 1. Аудит NaaS-контрактів (Slashing Protocol / Celo Rewards)
    ClusterHealthCheckWorker.perform_async(date_string)

    # 1b. [INS.1] Страховий оракул (Trigger-1, arm-кандидат) — per-cluster fan-out за майстер-
    # прапором :parametric_insurance_oracle_enabled (kill-switch, default off → інертно).
    # Settlement окремо за НЕЗАЛЕЖНИМ підтвердженням (dClimate / Field-Audit), 05_05 §6.
    enqueue_insurance_oracle(date_string)
  end

  private

  # [INS.1] Fan-out лише по кластерах з активними страховками; за прапором (kill-switch).
  def enqueue_insurance_oracle(date_string)
    return unless ActiveModel::Type::Boolean.new.cast(
      SystemParameter.current(:parametric_insurance_oracle_enabled, default: false)
    )

    Cluster.joins(:parametric_insurances).merge(ParametricInsurance.status_active)
           .distinct.find_each do |cluster|
      InsuranceOracleWorker.perform_async(cluster.id, date_string)
    end
  end
end
