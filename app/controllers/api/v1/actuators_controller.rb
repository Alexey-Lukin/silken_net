# frozen_string_literal: true

module Api
  module V1
    class ActuatorsController < BaseController
      before_action :authorize_forester!
      before_action :set_cluster, only: [ :index ]
      before_action :set_actuator, only: [ :show, :execute ]

      # --- РЕЄСТР ВИКОНАВЧИХ ВУЗЛІВ ---
      def index
        @actuators = @cluster.actuators.includes(:tree, :gateway)

        respond_to do |format|
          format.json { render json: @actuators }
          format.html do
            render_dashboard(
              title: "Actuators // Sector: #{@cluster.name}",
              component: Views::Components::Actuators::Index.new(cluster: @cluster, actuators: @actuators)
            )
          end
        end
      end

      # --- ДЕТАЛЬНИЙ АУДИТ ВУЗЛА ---
      def show
        @commands = @actuator.actuator_commands.order(created_at: :desc).limit(20)

        respond_to do |format|
          format.json { render json: { actuator: @actuator, history: @commands } }
          format.html do
            render_dashboard(
              title: "Actuator Hub // #{@actuator.actuator_type.upcase}",
              component: Views::Components::Actuators::Show.new(actuator: @actuator, commands: @commands)
            )
          end
        end
      end

      # --- ПРЯМЕ ВИКОНАННЯ КОМАНДИ ---
      def execute
        if @actuator.actuator_commands.pending.exists?
          return render json: { error: "Актуатор вже має активну команду. Зачекайте на її завершення." },
                        status: :conflict
        end

        @command = @actuator.actuator_commands.create!(
          user: current_user,
          command_payload: params[:action_payload],
          status: :pending
        )

        # Відправляємо команду в ефір (CoAP/LoRa)
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

      private

      def set_cluster
        @cluster = current_user.organization.clusters.find(params[:cluster_id])
      end

      def set_actuator
        @actuator = Actuator.joins(gateway: :cluster)
                            .where(clusters: { organization_id: current_user.organization_id })
                            .find(params[:id])
      end
    end
  end
end
