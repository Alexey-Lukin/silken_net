# frozen_string_literal: true

class DailyAggregationWorker
  include Sidekiq::Job

  # Пріоритет "low" для фонових задач, але сувора унікальність за датою.
  # lock: :until_executed гарантує, що ми не почнемо "стискати" той самий день двічі.
  sidekiq_options queue: "low", retry: 3, lock: :until_executed

  def perform(date_string = nil)
    # 1. ВИЗНАЧЕННЯ ЦІЛЬОВОЇ ДАТИ (The Project Pulse)
    target_date = if date_string.present?
                    Date.parse(date_string)
    else
                    Time.use_zone("Kyiv") { Date.yesterday }
    end

    Rails.logger.info "🕒 [Хронометрист] Початок великої агрегації за #{target_date}..."

    # 2. СТИСНЕННЯ РЕАЛЬНОСТІ (Insight Generation)
    # Цей сервіс перетворює мільйони логів телеметрії на добові звіти AiInsight.
    # Результат сервісу (успіх/кількість) допоможе нам зрозуміти, чи йти далі.
    aggregation_results = InsightGeneratorService.call(target_date)

    if aggregation_results[:processed_count].to_i.positive?
      # 3. ЗАМКНЕНИЙ ЦИКЛ (The Chaining)
      # [СИНХРОНІЗОВАНО]: Передаємо дату наступному воркеру.
      # Це гарантує, що Slashing Protocol та перевірка контрактів
      # відбудуться саме для тих даних, які ми щойно згенерували.
      ClusterHealthCheckWorker.perform_async(target_date.to_s)

      # Також варто перевірити параметричне страхування
      # ParametricInsuranceWorker.perform_async(target_date.to_s)

      Rails.logger.info "✅ [Хронометрист] Агрегація завершена (#{aggregation_results[:processed_count]} вузлів). Аудит контрактів заплановано."
    else
      Rails.logger.warn "⚠️ [Хронометрист] За #{target_date} не знайдено даних для агрегації. Ланцюг аудиту зупинено."

      # Якщо робочий день пройшов без жодного байта даних — це глобальна аварія зв'язку.
      # Сповіщаємо патрульних через EwsAlert для кожного активного кластера.
      if target_date.on_weekday?
        Cluster.joins(:naas_contracts).merge(NaasContract.status_active).distinct.find_each do |cluster|
          EwsAlert.create!(
            cluster_id: cluster.id,
            severity: :critical,
            alert_type: :system_fault,
            message: "🛰️ ГЛОБАЛЬНИЙ БЛЕКАУТ: За #{target_date} не надійшло жодних даних телеметрії. Можлива аварія Starlink або масовий відказ шлюзів."
          )
        end
      end
    end

  rescue Date::Error => e
    Rails.logger.error "🛑 [Хронометрист] Невірний формат дати: #{date_string}"
  rescue StandardError => e
    # Ми не використовуємо raise тут, якщо не хочемо, щоб Sidekiq нескінченно
    # намагався перерахувати день, який "зламався" (залежить від політики ретраїв).
    # Але для критичних збоїв — raise необхідний.
    Rails.logger.error "🛑 [Хронометрист] Критичний збій циклу агрегації: #{e.message}"
    raise e
  end
end
