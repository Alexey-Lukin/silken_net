# frozen_string_literal: true

# Codex::Attunement::Toggle — single button reflecting whether the current
# user is currently attuned to the host node. Optimistic UI is driven by
# the `codex--attune` Stimulus controller; the live counter rerenders via
# the `codex_node_<id>_attunements` Turbo Stream channel published by
# `Codex::AttunementBroadcastWorker`.
module Codex
  module Attunements
    class Toggle < ApplicationComponent
      def initialize(node:, current_user_attuned:, count:)
        @node     = node
        @attuned  = current_user_attuned
        @count    = count
      end

      def view_template
        div(
          class: tokens(
            "flex items-center justify-between gap-3",
            "border border-gaia-border bg-gaia-surface p-3"
          ),
          data: {
            controller: "codex--attune",
            "codex--attune-attuned-value": @attuned.to_s,
            "codex--attune-node-id-value": @node.id.to_s
          }
        ) do
          div(class: "space-y-0.5") do
            p(class: "text-mini uppercase tracking-[0.3em] text-gaia-text-muted") { "Attunement" }
            p(
              class: "text-tiny text-gaia-text-muted font-mono",
              id: dom_count_id,
              data: { "codex--attune-target": "count" }
            ) { @count.to_s }
          end

          form(
            action: api_v1_codex_node_attunements_path(@node.slug),
            method: @attuned ? "delete" : "post",
            data: { "codex--attune-target": "form" }
          ) do
            # Rails recognises _method override for non-POST verbs.
            input(type: "hidden", name: "_method", value: @attuned ? "delete" : "post")
            button(
              type: "submit",
              class: tokens(
                "inline-flex items-center gap-2 px-3 py-1 border focus-visible:ring-2 focus-visible:ring-gaia-primary",
                button_state_classes
              ),
              data: { "codex--attune-target": "button" }
            ) do
              span(class: "text-tiny uppercase tracking-[0.3em]") do
                @attuned ? "Attuned" : "Attune"
              end
            end
          end
        end
      end

      private

      def button_state_classes
        if @attuned
          "bg-status-success text-status-success-text border-status-success"
        else
          "bg-gaia-surface-alt text-gaia-text border-gaia-border hover:bg-gaia-primary hover:text-gaia-primary-text"
        end
      end

      def dom_count_id
        "codex_node_#{@node.id}_attunement_count"
      end
    end
  end
end
