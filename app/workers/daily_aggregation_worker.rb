# frozen_string_literal: true

class DailyAggregationWorker
  include Sidekiq::Job
  # Ця задача важка для БД, але не критична до мілісекунд (Low Priority)
  sidekiq_options queue: "low", retry: 3

  def perform(date_string = nil)
    # Якщо дата не передана, агрегуємо за вчорашній день (стандартний нічний запуск)
    target_date = date_string ? Date.parse(date_string) : Date.yesterday

    Rails.logger.info "🕒 [Хронометрист] Запуск агрегації телеметрії за #{target_date}..."

    # Делегуємо стиснення часу нашому сервісу
    InsightGeneratorService.call(target_date)

  rescue StandardError => e
    Rails.logger.error "🛑 [Хронометрист] Помилка агрегації: #{e.message}"
    raise e
  end
end
