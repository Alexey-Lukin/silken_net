# frozen_string_literal: true

class InsightGeneratorService
  def self.call(date = Date.yesterday)
    new(date).perform
  end

  def initialize(date)
    @date = date
    @start_time = date.beginning_of_day
    @end_time = date.end_of_day
    @processed_count = 0
  end

  def perform
    Rails.logger.info "🧠 [Insight Generator] Початок агрегації за #{@date}..."

    # 1. ІДЕМПОТЕНТНІСТЬ: Очищуємо старі інсайти за цю дату перед перерахунком
    AiInsight.where(target_date: @date, insight_type: :daily_health_summary).delete_all

    # 2. ПОТРУНКОВА ОБРОБКА ДЕРЕВ (The Soldier Nodes)
    Tree.find_each do |tree|
      if generate_for_tree(tree)
        @processed_count += 1
      end
    end

    # 3. АГРЕГАЦІЯ КЛАСТЕРІВ (The Big Picture)
    aggregate_clusters!

    # 4. КЕНОЗИС: Очищення сирих логів
    cleanup_old_logs!

    Rails.logger.info "✅ [Insight Generator] Цикл завершено. Оброблено вузлів: #{@processed_count}"
    
    # Повертаємо результат для DailyAggregationWorker
    { processed_count: @processed_count, date: @date }
  end

  private

  def generate_for_tree(tree)
    logs = tree.telemetry_logs.where(created_at: @start_time..@end_time)
    return false if logs.empty?

    # Агрегуємо фізичні показники одним SQL-запитом
    stats = logs.select(
      "AVG(temperature_c) as avg_temp",
      "AVG(voltage_mv) as avg_vcap",
      "AVG(z_value) as avg_z", 
      "MAX(acoustic_events) as max_acoustic",
      "SUM(growth_points) as total_growth",
      "MAX(bio_status) as max_status" 
    ).take

    return false unless stats&.avg_temp

    # Розраховуємо індекс стресу (враховуючи відхилення Z Атрактора)
    stress_index = calculate_stress_index(
      stats.max_status.to_i, 
      stats.avg_temp.to_f, 
      stats.max_acoustic.to_i, 
      stats.avg_z.to_f
    )

    AiInsight.create!(
      analyzable: tree,
      insight_type: :daily_health_summary,
      target_date: @date,
      average_temperature: stats.avg_temp.to_f.round(2),
      stress_index: stress_index,
      total_growth_points: stats.total_growth.to_i,
      summary: generate_summary(stats.max_status.to_i, stats.avg_temp.to_f),
      reasoning: { 
        avg_z: stats.avg_z.to_f.round(4), 
        max_acoustic: stats.max_acoustic.to_i,
        avg_vcap: stats.avg_vcap.to_i
      }
    )
    true
  rescue StandardError => e
    Rails.logger.error "🛑 [Insight] Помилка для Дерева #{tree.did}: #{e.message}"
    false
  end

  def calculate_stress_index(max_status, avg_temp, max_acoustic, avg_z)
    # Якщо зафіксовано статус 2 (Аномалія) або 3 (Вандалізм) — стрес максимальний
    return 1.0 if max_status >= 2 
    
    base_stress = (max_status == 1 ? 0.6 : 0.0)
    
    # [МАТЕМАТИКА ХАОСУ]: Якщо Z-index виходить за межі стабільної орбіти (abs > 2.0)
    # це ознака того, що система втрачає гомеостаз.
    base_stress += 0.2 if avg_z.abs > 2.0
    
    # Температурний стрес (екстремальні умови Черкаського бору)
    base_stress += 0.1 if avg_temp > 35.0 || avg_temp < -5.0
    
    # Максимальний стрес для "живого" дерева обмежений 0.99, 1.0 — це термінальний стан
    [base_stress, 0.99].min
  end

  def aggregate_clusters!
    Cluster.find_each do |cluster|
      # Збираємо вердикти всіх дерев кластера за вказану дату
      tree_insights = AiInsight.where(
        analyzable: cluster.trees, 
        insight_type: :daily_health_summary, 
        target_date: @date
      )
      
      next if tree_insights.empty?

      AiInsight.create!(
        analyzable: cluster,
        insight_type: :daily_health_summary,
        target_date: @date,
        stress_index: tree_insights.average(:stress_index).to_f.round(3),
        total_growth_points: tree_insights.sum(:total_growth_points),
        summary: "Сектор #{cluster.name}: Оброблено #{tree_insights.count} вузлів. Стан стабільний."
      )
    end
  end

  def cleanup_old_logs!
    # [КЕНОЗИС]: Ми зберігаємо лише 7 днів сирих даних для економії простору БД
    threshold = 7.days.ago.end_of_day
    deleted = TelemetryLog.where("created_at <= ?", threshold).delete_all
    Rails.logger.info "🧹 [Insight Generator] Видалено #{deleted} застарілих логів телеметрії."
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
