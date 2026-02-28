# frozen_string_literal: true

module Api
  module V1
    class ActuatorsController < BaseController
      # Тільки Патрульні та Адміни можуть віддавати накази "Рукам"
      before_action :authorize_forester!

      # --- ПЕРЕЛІК М'ЯЗІВ ---
      # GET /api/v1/clusters/:cluster_id/actuators
      def index
        @cluster = Cluster.find(params[:cluster_id])
        @actuators = @cluster.actuators.includes(:tree, :gateway)
        
        render json: @actuators.as_json(
          only: [:id, :actuator_type, :status, :last_command_at],
          include: {
            tree: { only: [:did] },
            gateway: { only: [:uid] }
          }
        )
      end

      # --- ПРЯМИЙ НАКАЗ (Manual Override) ---
      # POST /api/v1/actuators/:id/execute
      # Очікує: { action: 'open', duration: 300 } або { action: 'alarm_on' }
      def execute
        @actuator = Actuator.find(params[:id])
        
        # 1. Реєструємо наказ у базі (Audit Trail)
        @command = @actuator.actuator_commands.create!(
          user: current_user,
          command_payload: params[:action],
          status: :pending
        )

        # 2. ВІДПРАВКА В ЕФІР
        # [СИНХРОНІЗОВАНО]: EmergencyResponseService ініціює CoAP/LoRa Downlink
        # Ми не чекаємо відповіді від заліза, API повертає "Прийнято"
        EmergencyResponseService.dispatch_manual_command(@command.id)

        render json: { 
          message: "Наказ на #{@actuator.actuator_type} відправлено. Очікуємо підтвердження від заліза.",
          command_id: @command.id,
          status: :dispatched
        }, status: :accepted
      end

      # --- СТАН ВИКОНАННЯ ---
      # GET /api/v1/actuator_commands/:id
      def command_status
        @command = ActuatorCommand.find(params[:id])
        render json: { 
          id: @command.id,
          status: @command.status, # pending -> processing -> executed/failed
          executed_at: @command.executed_at 
        }
      end
    end
  end
end
