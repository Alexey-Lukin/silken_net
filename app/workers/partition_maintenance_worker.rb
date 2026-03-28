# frozen_string_literal: true

class PartitionMaintenanceWorker
  include Sidekiq::Job

  # Інфраструктурне обслуговування — стандартний пріоритет, 3 ретраї.
  # DDL-операція ідемпотентна, тому ретраї безпечні.
  sidekiq_options queue: "default", retry: 3

  # Таблиці з декларативним партиціюванням RANGE за created_at.
  PARTITIONED_TABLES = %w[telemetry_logs gateway_telemetry_logs].freeze

  def perform
    today = Time.current.utc.to_date
    months = [ today.beginning_of_month, (today + 1.month).beginning_of_month ]

    Rails.logger.info "🗂️ [Partition Maintenance] Перевірка партицій для #{months.map { _1.strftime('%Y-%m') }.join(', ')}..."

    created = 0

    PARTITIONED_TABLES.each do |table_name|
      months.each do |month_start|
        created += ensure_partition(table_name, month_start)
      end
    end

    Rails.logger.info "✅ [Partition Maintenance] Завершено. Створено нових партицій: #{created}"
  end

  private

  # Створює партицію для вказаної таблиці та місяця, якщо її ще не існує.
  # Повертає 1 якщо партицію було створено, 0 якщо вона вже існувала.
  def ensure_partition(table_name, month_start)
    conn = ActiveRecord::Base.connection
    partition_name = partition_name_for(table_name, month_start)
    range_from = month_start.strftime("%Y-%m-%d 00:00:00")
    range_to = (month_start + 1.month).strftime("%Y-%m-%d 00:00:00")

    sql = <<~SQL.squish
      CREATE TABLE IF NOT EXISTS #{conn.quote_table_name(partition_name)}
      PARTITION OF #{conn.quote_table_name(table_name)}
      FOR VALUES FROM (#{conn.quote(range_from)}) TO (#{conn.quote(range_to)})
    SQL

    conn.execute(sql)

    Rails.logger.info "🗂️ [Partition Maintenance] Партиція #{partition_name} — OK"
    1
  rescue ActiveRecord::StatementInvalid => e
    if e.message.include?("already exists")
      Rails.logger.info "🗂️ [Partition Maintenance] Партиція #{partition_name} вже існує — пропущено"
      0
    else
      Rails.logger.error "🛑 [Partition Maintenance] Помилка створення #{partition_name}: #{e.message}"
      raise
    end
  end

  # Генерує ім'я партиції у форматі, що використовується в проєкті:
  # telemetry_logs_y2026m03, gateway_telemetry_logs_y2026m04
  def partition_name_for(table_name, month_start)
    "#{table_name}_y#{month_start.strftime('%Y')}m#{month_start.strftime('%m')}"
  end
end
