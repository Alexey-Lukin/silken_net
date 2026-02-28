# frozen_string_literal: true

module Api
  module V1
    class ActuatorsController < BaseController
      before_action :authorize_forester!

      # GET /api/v1/clusters/:cluster_id/actuators
      def index
        @cluster = Cluster.find(params[:cluster_id])
        @actuators = @cluster.actuators.includes(:tree, :gateway)

        respond_to do |format|
          format.json do
            render json: @actuators.as_json(
              only: [ :id, :actuator_type, :status, :last_command_at ],
              include: {
                tree: { only: [ :did ] },
                gateway: { only: [ :uid ] }
              }
            )
          end
          format.html do
            render_dashboard(
              title: "Actuators // Sector: #{@cluster.name}",
              component: Views::Components::Actuators::Index.new(cluster: @cluster, actuators: @actuators)
            )
          end
        end
      end

      # POST /api/v1/actuators/:id/execute
      def execute
        @actuator = Actuator.find(params[:id])

        @command = @actuator.actuator_commands.create!(
          user: current_user,
          command_payload: params[:action],
          status: :pending
        )

        EmergencyResponseService.dispatch_manual_command(@command.id)

        respond_to do |format|
          format.json { render json: { command_id: @command.id, status: :accepted }, status: :accepted }
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "actuator_#{@actuator.id}",
              Views::Components::Actuators::Card.new(actuator: @actuator, last_command: @command).call
            )
          end
        end
      end

      # --- ПОВЕРНЕНО: СТАН ВИКОНАННЯ (The Audit Trace) ---
      # GET /api/v1/actuator_commands/:id
      def command_status
        @command = ActuatorCommand.find(params[:id])
        
        render json: {
          id: @command.id,
          actuator_id: @command.actuator_id,
          status: @command.status, # pending -> dispatched -> executed / failed
          payload: @command.command_payload,
          executed_at: @command.executed_at,
          response_metadata: @command.response_metadata # відповідь від заліза (CoAP/LoRa)
        }
      end
    end
  end
end
