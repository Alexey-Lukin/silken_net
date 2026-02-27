# frozen_string_literal: true

class ClusterHealthCheckWorker
  include Sidekiq::Job
  # Використовуємо чергу maintenance для фонових системних завдань
  sidekiq_options queue: "default", retry: 3

  def perform
    Rails.logger.info "🕵️ [D-MRV Audit] Початок перевірки активних NaaS контрактів: #{Time.current}"
    
    summary = { checked: 0, breached: 0, errors: 0 }

    # Використовуємо скоуп active_contracts, який ми прописали раніше
    NaasContract.status_active.find_each do |contract|
      summary[:checked] += 1
      
      begin
        # Виконуємо Slashing Protocol (перевірка порогу 20% аномалій)
        contract.check_cluster_health!
        
        if contract.status_breached?
          summary[:breached] += 1
          Rails.logger.warn "🚨 [D-MRV] Контракт ##{contract.id} (Кластер: #{contract.cluster.name}) ПОРУШЕНО!"
        end
        
      rescue StandardError => e
        summary[:errors] += 1
        Rails.logger.error "🛑 [D-MRV Error] Помилка аудиту контракту ##{contract.id}: #{e.message}"
        # Ми не перериваємо цикл, щоб перевірити інші ліси
        next
      end
    end

    Rails.logger.info "✅ [D-MRV Audit] Завершено. Оброблено: #{summary[:checked]}, Розірвано: #{summary[:breached]}, Помилок: #{summary[:errors]}"
  end
end
