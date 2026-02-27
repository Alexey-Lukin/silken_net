# frozen_string_literal: true

class InsightGeneratorService
  # За замовчуванням агрегуємо вчорашній день (викликається щоночі)
  def self.call(date = Date.yesterday)
    new(date).perform
  end

  def initialize(date)
    @date = date
    @start_time = date.beginning_of_day
    @end_time = date.end_of_day
  end

  def perform
    Rails.logger.info "🧠 [Insight Generator] Початок агрегації даних за #{@date}..."

    # Використовуємо find_each (батчинг по 1000), щоб не завантажувати весь ліс у RAM
    Tree.find_each do |tree|
      generate_for_tree(tree)
    end

    # СИСТЕМНИЙ КЕНОЗИС: Звільняємо посудину
    cleanup_old_logs!

    Rails.logger.info "✅ [Insight Generator] Агрегація за #{@date} успішно завершена."
  end

  private

  def generate_for_tree(tree)
    logs = tree.telemetry_logs.where(created_at: @start_time..@end_time)

    # Якщо вузол був офлайн (немає телеметрії), пропускаємо
    return if logs.empty?

    # ZERO-ALLOCATION MATH: Делегуємо всі обчислення базі даних PostgreSQL.
    # Це працює за мілісекунди і не створює тисячі Ruby-об'єктів.
    stats = logs.select(
      "AVG(temperature) as avg_temp",
      "AVG(vcap_voltage) as avg_vcap",
      "MAX(acoustic) as max_acoustic",
      "SUM(growth_points) as total_growth",
      "MAX(status_code) as max_status"
    ).take

    # Переконуємось, що дані існують
    return unless stats&.avg_temp

    avg_temp = stats.avg_temp.to_f.round(2)
    avg_vcap = stats.avg_vcap.to_i
    max_acoustic = stats.max_acoustic.to_i
    total_growth = stats.total_growth.to_i
    max_status = stats.max_status.to_i

    # Розрахунок комплексного індексу стресу
    stress_index = calculate_stress_index(max_status, avg_temp, max_acoustic)
    summary = generate_summary(max_status, avg_temp)

    # Зберігаємо "стиснуту" добу
    AiInsight.create!(
      tree: tree,
      analyzed_date: @date,
      average_temperature: avg_temp,
      stress_index: stress_index,
      total_growth_points: total_growth,
      summary: summary
    )

  rescue StandardError => e
    Rails.logger.error "🛑 [Insight Generator] Збій агрегації для Дерева #{tree.did}: #{e.message}"
  end

  def calculate_stress_index(max_status, avg_temp, max_acoustic)
    # 1.0 - Мертве/Знищене, 0.0 - Ідеальний гомеостаз
    return 1.0 if max_status == 2 || max_status == 3 # Пожежа або Вандалізм
    return 0.7 if max_status == 1 # Посуха (Сигнал від TinyML)

    # Якщо статус 0 (Норма), рахуємо мікро-стреси
    base_stress = 0.0
    base_stress += 0.3 if avg_temp > 35.0 || avg_temp < -10.0
    base_stress += 0.2 if max_acoustic > 150 # Фоновий шум лісорубів неподалік

    [base_stress, 0.99].min
  end

  def generate_summary(max_status, avg_temp)
    # У майбутньому цей блок може звертатися до LLM, але для стабільності зараз використовуємо детерміновану логіку
    case max_status
    when 3 then "Втрата цілісності корпусу. Можливе втручання браконьєрів."
    when 2 then "Критична аномалія емісії ксилеми або аномальні температури. Система працювала в режимі виживання."
    when 1 then "Дерево зазнало гідрологічного стресу. Середня температура #{avg_temp}°C."
    else "Гомеостаз стабільний. Рівень акустичних подій у нормі."
    end
  end

  def cleanup_old_logs!
    # ВИДАЛЕННЯ БЕЗ ЕҐО: Ми не тримаємо сирі дані вічно.
    # Залишаємо телеметрію лише за останні 7 днів для глибинного дебагу (якщо щось зламалося).
    # Використання .delete_all (замість destroy_all) працює безпосередньо в SQL і не тригерить колбеки.
    threshold = 7.days.ago.end_of_day
    deleted_count = TelemetryLog.where("created_at <= ?", threshold).delete_all
    
    Rails.logger.info "🧹 [Кенозис Даних] Звільнено дисковий простір: видалено #{deleted_count} сирих записів."
  end
end
