# frozen_string_literal: true

module Api
  module V1
    class TelemetryController < BaseController
      # --- ЖИВИЙ ПОТІК ІСТИНИ (The Pulse) ---
      # GET /api/v1/telemetry/live
      def live
        respond_to do |format|
          format.html do
            render_dashboard(
              title: "Live Telemetry // The Pulse",
              component: Telemetry::LiveStream.new
            )
          end
        end
      end

      # --- ДИХАННЯ СОЛДАТА (Існуючий метод) ---
      def tree_history
        @tree = current_user.organization.trees.find(params[:tree_id])
        days = (params[:days] || 7).to_i
        logs = @tree.telemetry_logs.where(created_at: days.days.ago..Time.current).order(:created_at)

        # Оптимізація: використовуємо pluck замість map для зменшення навантаження на пам'ять
        plucked = logs.pluck(:created_at, :z_value, :temperature_c)
        baseline = @tree.tree_family.baseline_impedance

        render json: {
          did: @tree.did,
          unit: "kOhm",
          timestamps: plucked.map { |row| row[0].to_i },
          impedance: plucked.map { |row| row[1].to_f.round(2) },
          temperature: plucked.map { |row| row[2].to_f.round(2) },
          stress_index: plucked.map { |row| (1.0 - (row[1].to_f / baseline)).round(3) }
        }
      end

      # --- ПУЛЬС КОРЛЕВИ (Існуючий метод) ---
      def gateway_history
        @gateway = current_user.organization.gateways.find(params[:gateway_id])
        days = (params[:days] || 7).to_i
        logs = @gateway.gateway_telemetry_logs.where(created_at: days.days.ago..Time.current).order(:created_at)

        # Оптимізація: використовуємо pluck замість map
        plucked = logs.pluck(:created_at, :voltage_mv, :cellular_signal_csq, :temperature_c)

        render json: {
          uid: @gateway.uid,
          timestamps: plucked.map { |row| row[0].to_i },
          voltage: plucked.map { |row| row[1] },
          signal: plucked.map { |row| row[2] },
          temp: plucked.map { |row| row[3] }
        }
      end
    end
  end
end
