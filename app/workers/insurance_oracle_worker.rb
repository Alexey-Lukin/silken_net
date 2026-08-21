# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = ===================================================================
# 🛰️ INSURANCE ORACLE WORKER (Trigger-1 — денний обхід страховок кластера)
# = ===================================================================
# [INS.1] Per-cluster fan-out з денного ланцюга (`InsightBatchCallbacks#on_success`,
# після `ClusterHealthCheckWorker`). Кожен job обходить активні `ParametricInsurance`
# свого кластера й кличе `evaluate_daily_health!` — це Trigger-1 (arm-кандидат), НЕ
# виплата (settlement — окремо за незалежним підтвердженням, 05_05 §6). За майстер-
# прапором :parametric_insurance_oracle_enabled (kill-switch).
#
# Per-cluster fan-out (як `InsightGeneratorOrchestratorWorker`) тримає планетарний
# масштаб: паралельно, незалежний retry, не вантажить серійний цикл слешинг-аудиту.
class InsuranceOracleWorker
  include Sidekiq::Job

  sidekiq_options queue: "default", retry: 3

  def perform(cluster_id, date_string = nil)
    # [INS.1 kill-switch] Re-check на вході (defense-in-depth): прапор міг злетіти між
    # enqueue і run; OFF → no-op (кандидати не озброюються).
    return unless oracle_enabled?

    cluster = Cluster.find_by(id: cluster_id)
    return unless cluster

    target_date = date_string.present? ? Date.parse(date_string) : AiInsight.reporting_date

    cluster.parametric_insurances.status_active.find_each do |insurance|
      insurance.evaluate_daily_health!(target_date)
    rescue StandardError => e
      # Ізолюємо збій однієї страховки — решта кластера досягає оракула.
      Rails.logger.error "🛑 [Insurance Oracle] Кластер ##{cluster_id} / страховка ##{insurance.id}: #{e.message}"
      next
    end
  rescue Date::Error => e
    # Той самий клас, що в `DailyAggregationWorker` (OPS.19, знайдено сиблінг-свіпом):
    # виняток не біндився, а провина приписувалась `date_string`, який за
    # замовчуванням `nil` — тоді дата приходить із `AiInsight.reporting_date`,
    # і вказувати на аргумент означає слати читача не туди.
    Rails.logger.error "🛑 [Insurance Oracle] Невірний формат дати (аргумент: #{date_string.inspect}): #{e.message}"
  end

  private

  def oracle_enabled?
    ActiveModel::Type::Boolean.new.cast(
      SystemParameter.current(:parametric_insurance_oracle_enabled, default: false)
    )
  end
end
