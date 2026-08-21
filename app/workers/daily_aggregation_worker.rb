# SPDX-License-Identifier: AGPL-3.0-or-later
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
    # [ARCH.100] Якір доби — з One-Home `AiInsight.reporting_date`: цей воркер ПИШЕ добу,
    # якою потім читатиме весь арбітраж, тож розходження тут коштує найдорожче.
    target_date = date_string.present? ? Date.parse(date_string) : AiInsight.reporting_date

    Rails.logger.info "🕒 [Хронометрист] Початок великої агрегації за #{target_date}..."

    # [A-3: Wiki 04_02 §11 — Sidekiq Batch для покластерної обробки]
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

      # [SLASH-1 gap-D] Робочий день без жодного байта — сигнатура force-majeure
      # (Starlink-блекаут / масовий відказ шлюзів), НЕ халатність лісника: burn на
      # ній був би false slash (05_05 §6 «масовий blackout = A ⇒ карати лісника за
      # вкрадений шлюз»). Тому :field_audit, а НЕ :system_fault — той сидить і в
      # comms_no_ack?-whitelist, і поза critical_unmaintained?-blacklist, тож
      # накручував би penalty_factor обома гілками одразу (стеля pf), причому
      # назавжди: резолвера в system_fault немає. Дзеркалить
      # ContractHealthCheckService#flag_data_blackout! (той самий факт, той самий
      # вибір типу); хелпер дедуплікує — багатоденний блекаут не плодить дубль щодоби.
      if target_date.on_weekday?
        Cluster.joins(:naas_contracts).merge(NaasContract.status_active).distinct.find_each do |cluster|
          EwsAlert.escalate_field_audit!(
            cluster: cluster,
            message_key: "global_blackout",
            message_params: { target_date: target_date }
          )
        end
      end
    end

  rescue Date::Error => e
    # ⚠️ Рядок доти казав «Невірний формат дати: #{date_string}» і робив ДВА
    # мовчазні припущення. Перше: деталь винятку не біндилась узагалі, тож
    # причина парс-збою гинула. Друге, гірше: провина приписувалась `date_string`,
    # а cron кличе воркер БЕЗ аргументу (`config/sidekiq.yml`) — тоді він `nil`,
    # лог друкує порожнечу, і читач шукає дефект у вході, якого не було.
    Rails.logger.error "🛑 [Хронометрист] Невірний формат дати (аргумент: #{date_string.inspect}): #{e.message}"
  rescue StandardError => e
    # Ми не використовуємо raise тут, якщо не хочемо, щоб Sidekiq нескінченно
    # намагався перерахувати день, який "зламався" (залежить від політики ретраїв).
    # Але для критичних збоїв — raise необхідний.
    Rails.logger.error "🛑 [Хронометрист] Критичний збій циклу агрегації: #{e.message}"
    raise e
  end
end
