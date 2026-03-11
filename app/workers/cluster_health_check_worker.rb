# frozen_string_literal: true

class ClusterHealthCheckWorker
  include Sidekiq::Job
  # Використовуємо чергу за замовчуванням. 3 ретраї — достатньо для логічних перевірок.
  sidekiq_options queue: "default", retry: 3

  def perform(date_string = nil)
    # 1. СИНХРОНІЗАЦІЯ ДАТИ (The Audit Anchor)
    # Якщо дата не передана, target_date = nil, і кожен кластер/контракт
    # використає свій часовий пояс (cluster.local_yesterday).
    # [Global Forest Anchor]: Прибрано хардкод "Kyiv" — тепер система масштабується
    # від Бразилії до Індонезії через timezone кожного кластера.
    target_date = Date.parse(date_string) if date_string.present?

    date_label = target_date ? " за #{target_date}" : ""
    Rails.logger.info "🕵️ [D-MRV Audit] Початок перевірки активних NaaS контрактів#{date_label}"

    # 1.5. ОНОВЛЕННЯ КЕШУ ЗДОРОВ'Я (Cached Health Index)
    # Перераховуємо health_index для всіх кластерів і зберігаємо в БД.
    # Кожен кластер використовує свій часовий пояс для визначення "вчора".
    Cluster.find_each { |c| c.recalculate_health_index!(target_date || c.local_yesterday) }

    summary = { checked: 0, breached: 0, errors: 0 }

    # 2. ПЕРЕВІРКА ПОРУШЕНЬ (The Slashing Protocol)
    # find_each захищає пам'ять сервера при великій кількості контрактів
    NaasContract.status_active.find_each do |contract|
      summary[:checked] += 1

      begin
        # Виконуємо Slashing Protocol, передаючи конкретну дату для аналізу
        # Якщо target_date nil — метод використає cluster.local_yesterday
        contract.check_cluster_health!(target_date || contract.cluster.local_yesterday)

        if contract.status_breached?
          summary[:breached] += 1
          Rails.logger.warn "🚨 [D-MRV] Контракт ##{contract.id} (Кластер: #{contract.cluster.name}) ПОРУШЕНО за станом на #{target_date}!"
        else
          # [Celo ReFi]: Позитивний зворотний зв'язок — якщо кластер здоровий,
          # нагороджуємо громаду cUSD через Celo.
          reward_date = target_date || contract.cluster.local_yesterday
          CeloRewardWorker.perform_async(contract.cluster_id, reward_date.to_s)
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
