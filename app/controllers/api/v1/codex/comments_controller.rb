# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    module Codex
      # POST /codex/nodes/:slug/comments
      #
      # Idempotency-Key required for JSON writes (per docs/04_03 §7) — keeps
      # mobile-network retries from creating duplicate posts.
      class CommentsController < BaseController
        IDEMPOTENCY_TTL = 24.hours

        before_action :set_node

        def create
          if request.format.json? && idempotency_key.blank?
            return render json: { error: "Idempotency-Key header is required for JSON writes." },
                          status: :bad_request
          end

          if (cached = read_idempotent_response)
            return render json: cached, status: :ok
          end

          comment = ::Codex::Comment.new(comment_params).tap do |c|
            c.user = current_user
            c.commentable = @node
          end
          authorize comment

          if comment.save
            payload = { data: ::Codex::CommentBlueprint.render_as_hash(comment) }
            cache_idempotent_response(payload)

            respond_to do |format|
              format.json { render json: payload, status: :created }
              format.html { redirect_to codex_node_path(@node.slug), success: I18n.t("flash.codex.comment_posted") }
            end
          else
            render json: { errors: comment.errors.full_messages },
                   status: :unprocessable_content
          end
        end

        private

        def set_node
          @node = ::Codex::Node.find_by!(slug: params[:node_slug])
        end

        def comment_params
          params.require(:comment).permit(:body_md, :parent_id)
        end

        def idempotency_key
          request.headers["Idempotency-Key"]
        end

        def idempotency_cache_key
          return nil if idempotency_key.blank?
          digest = Digest::SHA256.hexdigest(idempotency_key)
          "idempotency:codex:comments:#{current_user.id}:#{@node.id}:#{digest}"
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
