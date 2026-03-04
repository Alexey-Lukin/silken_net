# frozen_string_literal: true

class InsightGeneratorService
  # Поріг відхилення. Якщо вологість/температура дерева відрізняється від
  # середньої по кластеру більше ніж на 30%, це класифікується як фрод/аномалія.
  FRAUD_DEVIATION_THRESHOLD = 0.30

  # [UTC Anchor]: Канонічний UTC-якір для агрегації телеметрії.
  def self.call(date = Time.current.utc.to_date - 1)
    new(date).perform
  end

  def initialize(date)
    @date = date
    @start_time = date.beginning_of_day
    @end_time = date.end_of_day
    @processed_count = 0
  end

  def perform
    Rails.logger.info "🧠 [Insight Generator] Початок масової агрегації за #{@date}..."

    # 1. ІДЕМПОТЕНТНІСТЬ: Очищуємо старі інсайти за цю дату перед перерахунком
    AiInsight.where(target_date: @date, insight_type: :daily_health_summary).delete_all

    # ⚡ [ОПТИМІЗАЦІЯ N+1]: Завантажуємо Базлайни ВСІХ кластерів одним запитом перед циклом.
    # Це прибирає сотні важких JOIN запитів усередині Cluster.find_each.
    @baselines_map = prefetch_cluster_baselines

    # 2. ПОКЛАСТЕРНА ОБРОБКА З AI-GUARD
    Cluster.find_each do |cluster|
      cluster_baseline = @baselines_map[cluster.id]
      next unless cluster_baseline

      # Перевіряємо кожне дерево в кластері на відповідність базлайну
      cluster.trees.find_each do |tree|
        if generate_for_tree(tree, cluster_baseline)
          @processed_count += 1
        end
      end
    end

    # 3. АГРЕГАЦІЯ КЛАСТЕРІВ (Оптимізовано JSONB)
    aggregate_clusters!

    # 4. КЕНОЗИС: Очищення сирих логів
    cleanup_old_logs!

    Rails.logger.info "✅ [Insight Generator] Цикл завершено. Оброблено вузлів: #{@processed_count}"
    { processed_count: @processed_count, date: @date }
  end

  private

  # ⚡ [ANTI-N+1]: Агрегація базлайнів для всіх кластерів одним GROUP BY
  def prefetch_cluster_baselines
    TelemetryLog.joins(:tree)
                .where(created_at: @start_time..@end_time)
                .group("trees.cluster_id")
                .select(
                  "trees.cluster_id",
                  "AVG(temperature_c) as avg_temp",
                  "AVG(sap_flow) as avg_sap",
                  "AVG(z_value) as avg_z"
                ).each_with_object({}) do |row, hash|
                  hash[row.cluster_id] = {
                    temp: row.avg_temp.to_f,
                    sap: row.avg_sap.to_f,
                    z: row.avg_z.to_f
                  }
                end
  end

  def generate_for_tree(tree, baseline)
    logs = tree.telemetry_logs.where(created_at: @start_time..@end_time)
    return false if logs.empty?

    # Агрегуємо фізичні показники одним SQL-запитом
    stats = logs.select(
      "AVG(temperature_c) as avg_temp",
      "AVG(voltage_mv) as avg_vcap",
      "AVG(z_value) as avg_z",
      "AVG(sap_flow) as avg_sap",
      "MAX(acoustic_events) as max_acoustic",
      "SUM(growth_points) as total_growth",
      "MAX(bio_status) as max_status"
    ).take

    return false unless stats&.avg_temp

    # 🛡️ [AI FRAUD GUARD]: Перевірка на "занадто ідеальні" показники
    is_fraud = detect_fraud?(stats, baseline)

    # Якщо виявлено фрод - ми блокуємо ріст і максимізуємо стрес
    final_growth = is_fraud ? 0 : stats.total_growth.to_i

    # Розраховуємо індекс стресу (враховуючи відхилення Z Атрактора та Фрод)
    # $$Stress = \min(1.0, \text{base\_stress} + \text{anomaly\_penalties})$$
    stress_index = is_fraud ? 1.0 : calculate_stress_index(stats.max_status.to_i, stats.avg_temp.to_f, stats.max_acoustic.to_i, stats.avg_z.to_f)

    summary = is_fraud ? "🚨 КРИТИЧНО: Виявлено фрод-телеметрію (аномальне відхилення від кластера)." : generate_summary(stats.max_status.to_i, stats.avg_temp.to_f)

    AiInsight.create!(
      analyzable: tree,
      insight_type: :daily_health_summary,
      target_date: @date,
      average_temperature: stats.avg_temp.to_f.round(2),
      stress_index: stress_index,
      total_growth_points: final_growth,
      summary: summary,
      fraud_detected: is_fraud,
      reasoning: {
        avg_z: stats.avg_z.to_f.round(4),
        max_acoustic: stats.max_acoustic.to_i,
        avg_vcap: stats.avg_vcap.to_i,
        deviation_from_baseline: calculate_deviation(stats.avg_sap.to_f, baseline[:sap])
      }
    )

    # ⚡ [ВИПРАВЛЕНО: Жорсткий Slashing]:
    # Ми більше не "вбиваємо" дерево миттєво. Створюємо критичну тривогу для перевірки.
    # Це захищає інвестора від помилок ШІ, але зупиняє виплати до вердикту людини.
    if is_fraud
      AlertDispatchService.create_fraud_alert!(tree, "Виявлено фрод-телеметрію за #{@date}")
    end

    true
  rescue StandardError => e
    Rails.logger.error "🛑 [Insight] Помилка для Дерева #{tree.did}: #{e.message}"
    false
  end

  def detect_fraud?(stats, baseline)
    return false if baseline[:sap].zero?
    sap_deviation = calculate_deviation(stats.avg_sap.to_f, baseline[:sap])
    temp_deviation = calculate_deviation(stats.avg_temp.to_f, baseline[:temp])
    (sap_deviation > FRAUD_DEVIATION_THRESHOLD) && (temp_deviation > FRAUD_DEVIATION_THRESHOLD)
  end

  def calculate_deviation(value, base)
    return 0.0 if base.zero?
    ((value - base).abs / base).round(4)
  end

  def calculate_stress_index(max_status, avg_temp, max_acoustic, avg_z)
    return 1.0 if max_status >= 2
    base_stress = (max_status == 1 ? 0.6 : 0.0)
    base_stress += 0.2 if avg_z.abs > 2.0
    base_stress += 0.1 if avg_temp > 35.0 || avg_temp < -5.0
    [ base_stress, 0.99 ].min
  end

  def aggregate_clusters!
    Cluster.find_each do |cluster|
      tree_insights = AiInsight.where(
        analyzable_type: "Tree",
        analyzable_id: cluster.trees.select(:id),
        insight_type: :daily_health_summary,
        target_date: @date
      )

      next if tree_insights.empty?

      # ⚡ [ОПТИМІЗАЦІЯ]: Використовуємо boolean колонку замість JSONB @> оператора
      fraud_count = tree_insights.where(fraud_detected: true).count

      summary = if fraud_count > 0
                  "⚠️ Сектор #{cluster.name}: Виявлено #{fraud_count} вузлів із фрод-телеметрією."
      else
                  "Сектор #{cluster.name}: Оброблено #{tree_insights.count} вузлів. Стан стабільний."
      end

      AiInsight.create!(
        analyzable: cluster,
        insight_type: :daily_health_summary,
        target_date: @date,
        stress_index: tree_insights.average(:stress_index).to_f.round(3),
        total_growth_points: tree_insights.sum(:total_growth_points),
        summary: summary
      )
    end
  end

  def cleanup_old_logs!
    threshold = 7.days.ago.end_of_day
    TelemetryLog.where("created_at <= ?", threshold).delete_all
  end

  def generate_summary(status, temp)
    case status
    when 3 then "КРИТИЧНО: Виявлено фізичне пошкодження корпусу."
    when 2 then "АНОМАЛІЯ: Атрактор вказує на хворобу або шкідників."
    when 1 then "СТРЕС: Вузол реагує на зовнішнє середовище (#{temp.round(1)}°C)."
    else "ГОМЕОСТАЗ: Стан дерева ідеальний."
    end
  end
end
