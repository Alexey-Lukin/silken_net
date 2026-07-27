# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::Comments::Thread — chronological list of visible comments on a
# node, with an inline composer at the bottom.
#
# 🔴 NOT live. This docstring used to claim a `codex_node_<id>_comments` Turbo
# Stream subscription; the producer was raw ActionCable (never Turbo), nothing
# ever subscribed, and it was removed 2026-07-27 (UI.2 + SEC). New comments
# appear on reload.
module Codex
  module Comments
    class Thread < ApplicationComponent
      def initialize(node:, comments:, current_user:)
        @node = node
        @comments = comments
        @current_user = current_user
      end

      def view_template
        # [UI.2] controller — на СЕКЦІЇ: Stimulus-scope = елемент+нащадки, а
        # Form (target=form/body) рендериться sibling'ом списку — з controller
        # на div#list таргети форми були поза scope і Cmd/Ctrl+Enter був мертвий.
        section(class: "space-y-3", data: { controller: "codex--comment" }) do
          h3(class: "text-mini uppercase tracking-[0.4em] text-gaia-text-muted") { t("codex.comments.heading") }

          div(
            id: list_dom_id,
            class: "space-y-2",
            data: { "codex--comment-target": "list" }
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
