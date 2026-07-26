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

        # POST /api/v1/codex/citations
        def create
          if request.format.json? && idempotency_key.blank?
            return render json: { error: "Idempotency-Key header is required for JSON writes." },
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
            broadcast_citation(citation, target)

            render json: payload, status: :created
          else
            render json: { errors: citation.errors.full_messages },
                   status: :unprocessable_content
          end
        end

        # DELETE /api/v1/codex/citations/:id
        def destroy
          citation = ::Codex::Citation.find(params[:id])
          authorize citation, :destroy?

          target = citation.citable
          citation.destroy!
          broadcast_citation_removed(citation, target) if target
          head :no_content
        end

        private

        # `?citable_type=Tree&citable_id=123` query/body parameters. We re-validate
        # against `Codex::Citation::ALLOWED_CITABLE_TYPES` to resist arbitrary
        # constantize attempts, and resolve the class via an explicit allow-map
        # so static analysers (Brakeman) don't have to reason about runtime
        # `safe_constantize` calls. Returns `:bad_request` (400) on bogus type
        # so the client can distinguish from auth (401) / authorization (403)
        # / validation (422) failures.
        CITABLE_CLASS_MAP = {
          "Tree"         => -> { Tree },
          "Cluster"      => -> { Cluster },
          "AiInsight"    => -> { AiInsight },
          "EwsAlert"     => -> { EwsAlert },
          # `OracleVision` is the lore-facing rename of `AiInsight` (see
          # `Views::Components::OracleVisions::*`). The class itself was not
          # extracted — Phlex components alias the AR record at the view
          # boundary. The lambda checks `defined?(::OracleVision)` so the
          # day someone DOES extract a real `OracleVision < AiInsight` STI
          # subclass, this entry starts pointing to it without a code change.
          "OracleVision" => -> { defined?(::OracleVision) ? ::OracleVision : AiInsight },
          "NaasContract" => -> { NaasContract }
        }.freeze
        private_constant :CITABLE_CLASS_MAP

        def resolve_target!
          type   = params.require(:citable_type)
          loader = CITABLE_CLASS_MAP[type]
          if loader.nil?
            render json: { error: "Unsupported citable_type" }, status: :bad_request
            return nil
          end

          klass =
            begin
              loader.call
            rescue NameError
              nil
            end
          if klass.nil?
            render json: { error: "Unsupported citable_type" }, status: :bad_request
            return nil
          end

          klass.find(params.require(:citable_id))
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

        # Broadcast a Turbo Stream `append` so any open viewer of the
        # cited target sees the new pill instantly. Topic key includes
        # type+id so that two open tabs on different targets don't
        # cross-pollinate. Failure here must NOT roll back the citation.
        def broadcast_citation(citation, target)
          stream = "codex_citations:#{target.class.base_class.name}:#{target.id}"
          ActionCable.server.broadcast(
            stream,
            {
              op:   "append",
              data: ::Codex::CitationBlueprint.render_as_hash(citation)
            }
          )
        rescue StandardError => e
          Rails.logger.warn "[Codex::CitationsController] broadcast failed: #{e.class}: #{e.message}"
        end

        def broadcast_citation_removed(citation, target)
          stream = "codex_citations:#{target.class.base_class.name}:#{target.id}"
          ActionCable.server.broadcast(
            stream,
            { op: "remove", id: citation.id }
          )
        rescue StandardError => e
          Rails.logger.warn "[Codex::CitationsController] broadcast remove failed: #{e.class}: #{e.message}"
        end
      end
    end
  end
end
