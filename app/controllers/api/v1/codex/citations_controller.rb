# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    module Codex
      # Citations endpoint — Phase 6 cross-domain stitch (`docs/04_05` §1 bidirectional lore; ADR-CDX-9 citable allow-list).
      #
      # The lore layer is bidirectional: an EwsAlert can quote the
      # `chainsaw_protocol` Node, a Tree can quote the `roots-darwin-brain`
      # archetype, a Cluster can quote `mythos/yggdrasil`. This controller
      # is the only path through which such citations are minted.
      #
      # Authorization (Pundit `Codex::CitationPolicy`):
      #   * create  → forester+ (operational data quoting lore)
      #   * destroy → own within 24 h grace, or admin+
      #
      # Idempotency: `Idempotency-Key` header is required for JSON writes
      # — repeated retries of the same key return the cached response.
      # The DB-level UNIQUE `(codex_node_id, citable_type, citable_id, created_by_user_id)`
      # is the second line of defence and converts duplicates into 422.
      class CitationsController < BaseController
        IDEMPOTENCY_TTL = 24.hours

        # POST /codex/citations
        def create
          if request.format.json? && idempotency_key.blank?
            return render json: { error: I18n.t("flash.codex.idempotency_required") },
                          status: :bad_request
          end

          if (cached = read_idempotent_response)
            return render json: cached, status: :ok
          end

          authorize ::Codex::Citation, :create?

          node   = ::Codex::Node.find_by!(slug: params.require(:codex_node_slug))
          target = resolve_target!
          return if target.nil?  # `resolve_target!` already rendered 400

          citation = ::Codex::Citation.new(
            codex_node_id:    node.id,
            citable_type:     target.class.base_class.name,
            citable_id:       target.id,
            note:             params[:note].presence,
            created_by_user:  current_user
          )

          if citation.save
            payload = { data: ::Codex::CitationBlueprint.render_as_hash(citation) }
            cache_idempotent_response(payload)

            render json: payload, status: :created
          else
            render json: { errors: citation.errors.full_messages },
                   status: :unprocessable_content
          end
        end

        # DELETE /codex/citations/:id
        def destroy
          citation = ::Codex::Citation.find(params[:id])
          verify_citation_within_organization!(citation)
          authorize citation, :destroy?

          citation.destroy!
          head :no_content
        end

        private

        # [SEC.26] Друга половина класу: `Codex::CitationPolicy#destroy?` пускає
        # `admin_or_above?` без жодної org-умови, тож admin будь-якої організації
        # зносив би будь-яку цитату на платформі.
        #
        # Вісь тут — АВТОР, а не цитована ціль, і це не смак: ціль може бути вже
        # знищена (`citable` — поліморфний `optional: true`, FK-каскаду немає), а
        # скоуп по цілі зробив би осиротілу цитату НЕВИДАЛИМОЮ назавжди — тобто
        # вдарив би рівно по чесному власнику, лишивши атакера недоторканим.
        # `created_by_user_id` — NOT NULL, тож вісь автора визначена завжди; а після
        # скоупу `create` обидві осі збігаються, бо цитату вже не народити на чужій цілі.
        #
        # Власний запис пропускаємо ДО читання організації — інакше автор без
        # acting-організації не прибрав би навіть власну цитату.
        #
        # Гард стоїть ПЕРЕД `authorize`: чужа цитата має давати 404, а не 403,
        # інакше різниця кодів лишається existence-оракулом саме для тієї
        # популяції, проти якої гард і написаний.
        def verify_citation_within_organization!(citation)
          return if citation.created_by_user_id == current_user.id
          return if acting_organization!.users.exists?(id: citation.created_by_user_id)

          raise ActiveRecord::RecordNotFound
        end

        # `?citable_type=Tree&citable_id=123` query/body parameters. We re-validate
        # against `Codex::Citation::ALLOWED_CITABLE_TYPES` to resist arbitrary
        # constantize attempts, and resolve the target through an explicit allow-map
        # so static analysers (Brakeman) don't have to reason about runtime
        # `safe_constantize` calls. Returns `:bad_request` (400) on bogus type
        # so the client can distinguish from auth (401) / authorization (403)
        # / validation (422) failures.
        # [SEC.26] Кожен запис мапи віддає вже ОРГ-СКОУПЛЕНИЙ relation, а не клас.
        # Доти тут стояв голий `klass`, і `find` по ньому робив ціль глобальною:
        # forester організації А писав цитату на запис Б, і вона проступала на
        # дашборді ВЛАСНИКА — `Clusters::Show` · `Trees::Show` · `Alerts::Row` ·
        # `OracleVisions::ForecastCard` рендерять `Citation.for_target` без власного
        # org-фільтра, бо покладаються на те, що ціль уже скоупив контролер вище.
        # Скоуп живе в САМІЙ мапі, а не окремою перевіркою після `find`, і це несуче:
        # так «не існує» і «чуже» дають ОДНУ відповідь (404), інакше різниця кодів
        # лишалась би existence-оракулом по всій платформі.
        CITABLE_CLASS_MAP = {
          "Tree"         => ->(org) { org.trees },
          "Cluster"      => ->(org) { org.clusters },
          "AiInsight"    => ->(org) { AiInsight.for_organization(org) },
          "EwsAlert"     => ->(org) { org.ews_alerts },
          # `OracleVision` — lore-фасад того самого `AiInsight` (Phlex-компоненти
          # перейменовують запис на межі в'ю). Окремого STI-підкласу тут не буде:
          # `ai_insights` не має колонки `type`, тож Rails не додав би type-умову
          # навіть існуй такий клас, а `base_class` однаково лишається `AiInsight`
          # — саме його й пише `citable_type` нижче.
          "OracleVision" => ->(org) { AiInsight.for_organization(org) },
          "NaasContract" => ->(org) { org.naas_contracts }
        }.freeze
        private_constant :CITABLE_CLASS_MAP

        def resolve_target!
          type  = params.require(:citable_type)
          scope = CITABLE_CLASS_MAP[type]
          if scope.nil?
            render json: { error: "Unsupported citable_type" }, status: :bad_request
            return nil
          end

          scope.call(acting_organization!).find(params.require(:citable_id))
        end

        def idempotency_key
          request.headers["Idempotency-Key"]
        end

        def idempotency_cache_key
          return nil if idempotency_key.blank?
          digest = Digest::SHA256.hexdigest(idempotency_key)
          "idempotency:codex:citations:#{current_user.id}:#{digest}"
        end

        def read_idempotent_response
          key = idempotency_cache_key
          return nil if key.blank?
          Rails.cache.read(key)
        end

        def cache_idempotent_response(payload)
          key = idempotency_cache_key
          return if key.blank?
          Rails.cache.write(key, payload, expires_in: IDEMPOTENCY_TTL)
        end
      end
    end
  end
end
