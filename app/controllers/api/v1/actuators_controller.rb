# frozen_string_literal: true

module Api
  module V1
    class ActuatorsController < BaseController
      before_action :authorize_forester!
      before_action :set_cluster, only: [ :index ]
      before_action :set_actuator, only: [ :show, :execute ]

      # --- РЕЄСТР ВИКОНАВЧИХ ВУЗЛІВ ---
      def index
        @pagy, @actuators = pagy(@cluster.actuators.includes(:gateway, :commands))

        respond_to do |format|
          format.json do
            render json: {
              data: @actuators,
              pagy: pagy_metadata(@pagy)
            }
          end
          format.html do
            active_count = @cluster.actuators.where(state: :active).count
            render_dashboard(
              title: "Actuators // Sector: #{@cluster.name}",
              component: Actuators::Index.new(cluster: @cluster, actuators: @actuators, pagy: @pagy, active_count: active_count)
            )
          end
        end
      end

      # --- ДЕТАЛЬНИЙ АУДИТ ВУЗЛА ---
      def show
        @commands = @actuator.commands.order(created_at: :desc).limit(20)

        respond_to do |format|
          format.json { render json: { actuator: @actuator, history: @commands } }
          format.html do
            render_dashboard(
              title: "Actuator Hub // #{@actuator.device_type.upcase}",
              component: Actuators::Show.new(actuator: @actuator, commands: @commands)
            )
          end
        end
      end

      # --- ПРЯМЕ ВИКОНАННЯ КОМАНДИ ---
      # [IDEMPOTENCY FIX]: POST /api/v1/actuators/:id/execute requires Idempotency-Key header
      # for JSON requests. This prevents duplicate physical actuations caused by network retries
      # (e.g., ranger's mobile app in forest with poor connectivity).
      # Cached responses are stored in Redis with 24h TTL — subsequent requests with the
      # same key return the original response without creating a new command.
      def execute
        idempotency_key = request.headers["Idempotency-Key"]

        if request.format.json? && idempotency_key.blank?
          return render json: { error: I18n.t("flash.actuators.idempotency_required") },
                        status: :bad_request
        end

        # Check idempotency cache for JSON requests with key
        if idempotency_key.present?
          cache_key = "idempotency:actuator:#{@actuator.id}:#{Digest::SHA256.hexdigest(idempotency_key)}"
          cached = Rails.cache.read(cache_key)
          if cached
            return render json: cached, status: :accepted
          end
        end

        if @actuator.commands.pending.exists?
          return render json: { error: I18n.t("flash.actuators.command_in_flight") },
                        status: :conflict
        end

        @command = @actuator.commands.create!(
          user: current_user,
          command_payload: params[:action_payload],
          duration_seconds: params[:duration_seconds],
          status: :issued
        )

        # Команда автоматично диспетчеризується через after_commit :dispatch_to_edge!

        respond_to do |format|
          format.json do
            response_body = { command_id: @command.id, status: "accepted" }

            # [PUMA-RACK-1]: Store in idempotency cache AFTER response is flushed to client.
            # rack.response_finished callback (Puma 7.0+) executes after the response body
            # is sent, saving ~1-2ms from the critical path.
            if idempotency_key.present?
              cached_key = cache_key
              cached_body = response_body
              request.env["rack.response_finished"] ||= []
              request.env["rack.response_finished"] << ->(_env) {
                Rails.cache.write(cached_key, cached_body, expires_in: 24.hours)
              }
            end

            render json: response_body, status: :accepted
          end
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "actuator_#{@actuator.id}",
              Actuators::Card.new(actuator: @actuator, last_command: @command).call
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
