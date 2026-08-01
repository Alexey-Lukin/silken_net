# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    class ActuatorsController < BaseController
      before_action :authorize_forester!
      before_action :set_cluster, only: [ :index ]
      before_action :set_actuator, only: [ :show, :execute ]
      before_action :set_command, only: [ :command_status ]

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
              title: I18n.t("actuators.index_title", name: @cluster.name),
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
              title: I18n.t("actuators.show_title", device_type: @actuator.device_type.upcase),
              component: Actuators::Show.new(actuator: @actuator, commands: @commands)
            )
          end
        end
      end

      # --- ПРЯМЕ ВИКОНАННЯ КОМАНДИ ---
      # [IDEMPOTENCY FIX]: POST /actuators/:id/execute requires Idempotency-Key header
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

        # [ARCH.58] In-flight гард НЕ поширюється на override (STOP/EMERGENCY_*):
        # інакше оператор не може подати аварійну зупинку саме тоді, коли в черзі
        # щось є — тобто в єдиному сценарії, заради якого override існує. Сам
        # override далі скасовує pending (`cancel_pending_for_actuator!`), тож
        # «дві команди в польоті» тут не виникає. Дзеркало винятку в
        # `ActuatorCommand#dispatch_to_edge!`; без обох половин STOP лишався
        # недосяжним — модельну ми відкрили, а контролер віддавав 409.
        # `live_pending`, а НЕ `pending`: протермінований наказ матеріалізує свій
        # кінець лише при poll-видачі, тож на мертвому шлюзі труп інакше тримав би
        # 409 назавжди — і TTL цього не лікує, бо гард його не бачить.
        if @actuator.commands.live_pending.exists? && !override_payload?
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
            # Rack SPEC: callables are invoked with (env, status, headers, error) — a
            # narrower lambda raises ArgumentError that Puma swallows into debug logs,
            # silently skipping the cache write (retry would double-actuate hardware).
            #
            # `idempotency_key` is unconditionally present in this branch: the guard
            # above (`if request.format.json? && idempotency_key.blank? → 400`) already
            # rejected a blank key for any request that resolves to this `format.json`
            # block, so no `if idempotency_key.present?` re-check is needed here.
            cached_key = cache_key
            cached_body = response_body
            request.env["rack.response_finished"] ||= []
            request.env["rack.response_finished"] << ->(_env, _status, _headers, _error) {
              Rails.cache.write(cached_key, cached_body, expires_in: 24.hours)
            }

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

      # --- СТАТУС КОМАНДИ (Audit Trail) ---
      # GET /actuator_commands/:id
      # Documented as endpoint #48 in 04_03 §4 but was missing from the controller
      # before this fix. The route resolved to NoMethodError at runtime.
      def command_status
        # ⚠️ Порядок гілок НЕ косметика: на `Accept: */*` (дефолт curl і багатьох
        # SDK) Rails віддає ПЕРШИЙ оголошений формат. JSON тут первинний — це
        # документований API-ендпоінт (#48 у `04_03 §4`), і `index`/`show` цього
        # ж контролера теж ведуть з json. Turbo-frame шле явний `Accept: text/html`,
        # тож від порядку не залежить.
        respond_to do |format|
          format.json do
            render json: {
              id: @command.id,
              actuator_id: @command.actuator_id,
              status: @command.status,
              priority: @command.priority,
              command_payload: @command.command_payload,
              duration_seconds: @command.duration_seconds,
              issued_at: @command.created_at,
              sent_at: @command.sent_at,
              executed_at: @command.executed_at,
              error_message: @command.error_message,
              expires_at: @command.expires_at
            }
          end

          # [I18N.2 · клас 2] Turbo-frame тягне СВІЙ фрагмент власним запитом —
          # тобто вже з локаллю глядача (`LocaleSettable` тут відпрацював) і його
          # ж авторизацією (`set_command` org-скоупований). Саме це дозволяє
          # броадкасту не нести жодного перекладеного слова.
          #
          # ⚠️ Фрейм у відповіді — БЕЗ `src`. Не «щоб не було циклу»: Turbo ловить
          # self-referencing src, кидає в консоль `references itself` і лишає фрейм
          # ПОРОЖНІМ — тобто ціна помилки не нескінченний трафік, а назавжди порожня
          # клітинка й тиха помилка, яку ніхто не побачить.
          format.html do
            render Actuators::CommandStatusFrame.new(command: @command), layout: false
          end
        end
      end

      private

      # [ARCH.58] Дім деривації — модель (`ActuatorCommand.override_payload?`),
      # тут лише читання params до створення запису.
      def override_payload?
        ActuatorCommand.override_payload?(params[:action_payload])
      end

      def set_command
        @command = ActuatorCommand.joins(actuator: { gateway: :cluster })
                                  .where(clusters: { organization_id: acting_organization!.id })
                                  .find(params[:id])
      end

      def set_cluster
        @cluster = acting_organization!.clusters.find(params[:cluster_id])
      end

      def set_actuator
        @actuator = Actuator.joins(gateway: :cluster)
                            .where(clusters: { organization_id: acting_organization!.id })
                            .find(params[:id])
      end
    end
  end
end
