# frozen_string_literal: true

class ClusterHealthCheckWorker
  include Sidekiq::Job
  # Використовуємо чергу за замовчуванням. 3 ретраї — достатньо для логічних перевірок.
  sidekiq_options queue: "default", retry: 3

  def perform(date_string = nil)
    # 1. СИНХРОНІЗАЦІЯ ДАТИ (The Audit Anchor)
    # Якщо дата не передана, використовуємо вчорашній день за Києвом.
    target_date = if date_string.present?
                    Date.parse(date_string)
                  else
                    Time.use_zone("Kyiv") { Date.yesterday }
                  end

    Rails.logger.info "🕵️ [D-MRV Audit] Початок перевірки активних NaaS контрактів за #{target_date}"
    
    summary = { checked: 0, breached: 0, errors: 0 }

    # 2. ПЕРЕВІРКА ПОРУШЕНЬ (The Slashing Protocol)
    # find_each захищає пам'ять сервера при великій кількості контрактів
    NaasContract.status_active.find_each do |contract|
      summary[:checked] += 1
      
      begin
        # Виконуємо Slashing Protocol, передаючи конкретну дату для аналізу
        # Метод check_cluster_health! тепер знає, за який день шукати аномалії в AiInsight
        contract.check_cluster_health!(target_date)
        
        if contract.status_breached?
          summary[:breached] += 1
          Rails.logger.warn "🚨 [D-MRV] Контракт ##{contract.id} (Кластер: #{contract.cluster.name}) ПОРУШЕНО за станом на #{target_date}!"
        end
        
      rescue StandardError => e
        summary[:errors] += 1
        Rails.logger.error "🛑 [D-MRV Error] Помилка аудиту контракту ##{contract.id}: #{e.message}"
        # Продовжуємо аудит наступних лісів
        next
      end
    end

    Rails.logger.info "✅ [D-MRV Audit] Завершено. Оброблено: #{summary[:checked]}, Розірвано: #{summary[:breached]}, Помилок: #{summary[:errors]}"
  end
end
