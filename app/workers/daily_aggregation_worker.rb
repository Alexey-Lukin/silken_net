# frozen_string_literal: true

class DailyAggregationWorker
  include Sidekiq::Job

  # Пріоритет "low" для фонових задач, але сувора унікальність за датою.
  # [UNIQUE_FOR]: Sidekiq Enterprise Unique Jobs замінює стороннє lock: :until_executed.
  # Нативна реалізація ефективніша (Redis SETNX замість Lua-скриптів)
  # та підтримується Sidekiq core team.
  sidekiq_options queue: "low", retry: 3, unique_for: 24.hours

  def perform(date_string = nil)
    # 1. ВИЗНАЧЕННЯ ЦІЛЬОВОЇ ДАТИ (The Project Pulse)
    # [UTC Anchor]: Використовуємо UTC як канонічний якір для агрегації телеметрії.
    # Прибрано хардкод "Kyiv" — UTC забезпечує детермінованість для глобальних операцій.
    target_date = if date_string.present?
                    Date.parse(date_string)
    else
                    Time.current.utc.to_date - 1
    end

    Rails.logger.info "🕒 [Хронометрист] Початок великої агрегації за #{target_date}..."

    # [A-3: Wiki 04_02 §14 — Sidekiq Batch для покластерної обробки]
    # Замість синхронного InsightGeneratorService.call (OOM-ризик при 10M+ дерев),
    # запускаємо батч-оркестратор. InsightBatchCallbacks#on_success автоматично
    # запустить ClusterHealthCheckWorker після завершення всіх чанків.
    #
    # Перевіряємо наявність телеметрії перед запуском батчу.
    # EDGE CASE: якщо телеметрія існує, але всі дерева неактивні —
    # оркестратор побачить порожній cluster_baselines і поверне nil без запуску батчу.
    # ClusterHealthCheckWorker НЕ запуститься в цьому випадку. Це прийнятно:
    # якщо немає активних дерев — аудит NaaS контрактів не потрібен.
    has_telemetry = TelemetryLog.where(created_at: target_date.beginning_of_day..target_date.end_of_day).exists?

    if has_telemetry
      InsightGeneratorOrchestratorWorker.perform_async(target_date.to_s)

      Rails.logger.info "✅ [Хронометрист] Дані є за #{target_date}. Батч-агрегацію запущено."
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
