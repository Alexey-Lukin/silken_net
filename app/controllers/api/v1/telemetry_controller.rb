# frozen_string_literal: true

module Api
  module V1
    class TelemetryController < BaseController
      # --- ДИХАННЯ СОЛДАТА (Tree Impedance & Temp) ---
      # GET /api/v1/trees/:tree_id/telemetry
      # Параметри: ?days=7&resolution=hourly
      def tree_history
        @tree = Tree.find(params[:tree_id])
        days = (params[:days] || 7).to_i
        
        # Агрегуємо дані, щоб фронтенд не "впав" від 10,000 точок
        # Використовуємо середнє значення за годину (hourly average)
        logs = @tree.telemetry_logs
                    .where(created_at: days.days.ago..Time.current)
                    .order(:created_at)

        # Перетворюємо в формат, зручний для Chart.js / ApexCharts
        render json: {
          did: @tree.did,
          unit: "kOhm",
          timestamps: logs.map { |l| l.created_at.to_i },
          impedance: logs.map { |l| l.z_value.to_f.round(2) },
          temperature: logs.map { |l| l.temperature_c.to_f.round(2) },
          stress_index: logs.map { |l| (1.0 - (l.z_value.to_f / @tree.tree_family.baseline_impedance)).round(3) }
        }
      end

      # --- ПУЛЬС КОРЛЕВИ (Gateway Diagnostics) ---
      # GET /api/v1/gateways/:gateway_id/telemetry
      def gateway_history
        @gateway = Gateway.find(params[:gateway_id])
        days = (params[:days] || 7).to_i

        logs = @gateway.gateway_telemetry_logs
                       .where(created_at: days.days.ago..Time.current)
                       .order(:created_at)

        render json: {
          uid: @gateway.uid,
          timestamps: logs.map { |l| l.created_at.to_i },
          voltage: logs.map { |l| l.voltage_mv },
          signal: logs.map { |l| l.cellular_signal_csq },
          temp: logs.map { |l| l.temperature_c }
        }
      end
    end
  end
end
