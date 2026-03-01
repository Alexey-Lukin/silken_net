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
              component: Views::Components::Telemetry::LiveStream.new
            )
          end
        end
      end

      # --- ДИХАННЯ СОЛДАТА (Існуючий метод) ---
      def tree_history
        @tree = Tree.find(params[:tree_id])
        days = (params[:days] || 7).to_i
        logs = @tree.telemetry_logs.where(created_at: days.days.ago..Time.current).order(:created_at)

        render json: {
          did: @tree.did,
          unit: "kOhm",
          timestamps: logs.map { |l| l.created_at.to_i },
          impedance: logs.map { |l| l.z_value.to_f.round(2) },
          temperature: logs.map { |l| l.temperature_c.to_f.round(2) },
          stress_index: logs.map { |l| (1.0 - (l.z_value.to_f / @tree.tree_family.baseline_impedance)).round(3) }
        }
      end

      # --- ПУЛЬС КОРЛЕВИ (Існуючий метод) ---
      def gateway_history
        @gateway = Gateway.find(params[:gateway_id])
        days = (params[:days] || 7).to_i
        logs = @gateway.gateway_telemetry_logs.where(created_at: days.days.ago..Time.current).order(:created_at)

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
