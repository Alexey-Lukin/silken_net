# frozen_string_literal: true

# Codex::Citations::Strip — wrap-flex container of citation pills attached
# to a single operational target (Tree / Cluster / EwsAlert / OracleVision).
#
# Subscribes to the `codex_citations:<Type>:<ID>` ActionCable stream so a
# pill posted by a forester appears live for any open viewer.
#
# Render contract:
#   render Codex::Citations::Strip.new(target: @tree, citations: citations)
#
# `citations` is the eager-loaded slice — pass `Codex::Citation.for_target(target).includes(:node)`
# or, for tables, use `Codex::Citation.bulk_for(targets)[[type, id]]` to avoid N+1.
module Codex
  module Citations
    class Strip < ApplicationComponent
      def initialize(target:, citations:, current_user: nil)
        @target       = target
        @citations    = Array(citations)
        @current_user = current_user
      end

      def view_template
        div(
          id:   dom_id,
          class: "flex flex-wrap items-center gap-1.5"
        ) do
          if @citations.empty?
            span(class: "text-micro text-gaia-text-muted italic") do
              "No lore citations yet."
            end
          else
            @citations.each do |citation|
              render Pill.new(citation: citation)
            end
          end
        end
      end

      private

      def dom_id
        type = @target.class.base_class.name
        "codex_citations_#{type.underscore}_#{@target.id}"
      end
    end
  end
end
