# frozen_string_literal: true

# Codex::Comments::Thread — chronological list of visible comments on a
# node, with an inline composer at the bottom. Subscribes to the
# `codex_node_<id>_comments` Turbo Stream channel for live appends.
module Codex
  module Comments
    class Thread < ApplicationComponent
      def initialize(node:, comments:, current_user:)
        @node = node
        @comments = comments
        @current_user = current_user
      end

      def view_template
        section(class: "space-y-3") do
          h3(class: "text-mini uppercase tracking-[0.4em] text-gaia-text-muted") { t("codex.comments.heading") }

          div(
            id: list_dom_id,
            class: "space-y-2",
            data: { controller: "codex--comment", "codex--comment-target": "list" }
          ) do
            if @comments.empty?
              p(class: "text-tiny text-gaia-text-muted italic") { t("codex.comments.empty") }
            else
              @comments.each do |comment|
                render Codex::Comments::Item.new(comment: comment)
              end
            end
          end

          render Codex::Comments::Form.new(node: @node) if @current_user.present?
        end
      end

      private

      def list_dom_id
        "codex_node_#{@node.id}_comments"
      end
    end
  end
end
