# frozen_string_literal: true

class AddLatestVoltageMvToGateways < ActiveRecord::Migration[8.1]
  def change
    # Денормалізована колонка для швидкої перевірки стану батареї/панелі Королеви
    # без JOIN до gateway_telemetry_logs. Оновлюється через mark_seen!.
    add_column :gateways, :latest_voltage_mv, :integer
  end
end
