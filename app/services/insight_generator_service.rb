# frozen_string_literal: true

class InsightGeneratorService
  def self.call(date = Date.yesterday)
    new(date).perform
  end

  def initialize(date)
    @date = date
    @start_time = date.beginning_of_day
    @end_time = date.end_of_day
  end

  def perform
    Rails.logger.info "🧠 [Insight Generator] Початок агрегації за #{@date}..."

    # Обробляємо дерева батчами (мінімізація пам'яті)
    Tree.find_each do |tree|
      generate_for_tree(tree)
    end

    # Агрегація на рівні Кластерів (Big Picture для інвесторів)
    aggregate_clusters!

    cleanup_old_logs!
    Rails.logger.info "✅ [Insight Generator] Цикл завершено."
  end

  private

  def generate_for_tree(tree)
    logs = tree.telemetry_logs.where(created_at: @start_time..@end_time)
    return if logs.empty?

    # [АЛІГНЕМЕНТ]: Додаємо середнє z_value для аналізу Атрактора
    # [ВИПРАВЛЕНО]: bio_status — це вже integer в БД (0..3), тому MAX(bio_status) працює ідеально
    stats = logs.select(
      "AVG(temperature_c) as avg_temp",
      "AVG(voltage_mv) as avg_vcap",
      "AVG(z_value) as avg_z", 
      "MAX(acoustic_events) as max_acoustic",
      "SUM(growth_points) as total_growth",
      "MAX(bio_status) as max_status" 
    ).take

    return unless stats&.avg_temp

    # Розраховуємо індекс стресу (враховуючи відхилення Z)
    stress_index = calculate_stress_index(stats.max_status.to_i, stats.avg_temp.to_f, stats.max_acoustic.to_i, stats.avg_z.to_f)

    AiInsight.create!(
      analyzable: tree,
      insight_type: :daily_health_summary, # [СИНХРОНІЗАЦІЯ]: Обов'язкове поле моделі
      target_date: @date,                  # [СИНХРОНІЗАЦІЯ]: Відповідає валідації моделі
      average_temperature: stats.avg_temp.to_f.round(2),
      stress_index: stress_index,
      total_growth_points: stats.total_growth.to_i,
      summary: generate_summary(stats.max_status.to_i, stats.avg_temp.to_f),
      reasoning: { 
        avg_z: stats.avg_z.to_f.round(4), 
        max_acoustic: stats.max_acoustic.to_i 
      }
    )
  rescue StandardError => e
    Rails.logger.error "🛑 [Insight] Помилка для Дерева #{tree.did}: #{e.message}"
  end

  def calculate_stress_index(max_status, avg_temp, max_acoustic, avg_z)
    return 1.0 if max_status >= 2 # Аномалія/Вандалізм
    
    base_stress = (max_status == 1 ? 0.6 : 0.0)
    
    # [ФІЗИКА]: Якщо Z-index (Атрактор) виходить за межі стабільності (> 2.0)
    base_stress += 0.2 if avg_z.abs > 2.0
    base_stress += 0.1 if avg_temp > 35.0 || avg_temp < -5.0
    
    [base_stress, 0.99].min
  end

  # Агрегація для Кластерів (для дашборду Організації)
  def aggregate_clusters!
    Cluster.find_each do |cluster|
      # Збираємо середній стрес по всіх інсайтах дерев кластера за сьогодні
      tree_insights = AiInsight.where(
        analyzable: cluster.trees, 
        insight_type: :daily_health_summary, 
        target_date: @date
      )
      
      next if tree_insights.empty?

      AiInsight.create!(
        analyzable: cluster,
        insight_type: :daily_health_summary, # [СИНХРОНІЗАЦІЯ]
        target_date: @date,                  # [СИНХРОНІЗАЦІЯ]
        stress_index: tree_insights.average(:stress_index),
        total_growth_points: tree_insights.sum(:total_growth_points),
        summary: "Кластер #{cluster.name}: Оброблено #{tree_insights.count} вузлів."
      )
    end
  end

  def cleanup_old_logs!
    # Видаляємо лише те, що старше 7 днів
    threshold = 7.days.ago.end_of_day
    deleted = TelemetryLog.where("created_at <= ?", threshold).delete_all
    Rails.logger.info "🧹 [Кенозис] Видалено #{deleted} старих логів."
  end

  def generate_summary(status, temp)
    case status
    when 3 then "Критично: Порушення цілісності пристрою."
    when 2 then "Аномалія: Виявлено зовнішній вплив або хворобу."
    when 1 then "Стрес: Потрібен додатковий огляд (Темп: #{temp.round(1)}°C)."
    else "Стабільно: Вузол у стані гомеостазу."
    end
  end
end
