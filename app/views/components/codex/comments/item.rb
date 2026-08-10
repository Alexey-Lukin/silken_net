# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::Comments::Item — single comment row, used inside `Codex::Comments::Thread`.
# 🔴 NOT a broadcast target: the `codex_node_<id>_comments` stream has no producer
# (`Thread` already carries that correction; this docstring kept claiming it).
module Codex
  module Comments
    class Item < ApplicationComponent
      def initialize(comment:)
        @comment = comment
      end

      def view_template
        article(
          id: dom_id,
          class: tokens(
            "border border-gaia-border bg-gaia-surface p-3 space-y-1",
            ("opacity-50 italic" if @comment.hidden?)
          )
        ) do
          header(class: "flex items-center justify-between text-tiny font-mono text-gaia-text-muted") do
            # `&.` is model-validation-dead, not real: `Comment#user` is a
            # required belongs_to and `user_id` carries a plain FK (no
            # `ON DELETE` cascade/nullify) — the referenced user can't be
            # removed while the comment exists, so `.user` is always present.
            # [TEST.12] `full_name` тут був витоком: він падає на `email_address`,
            # а імена не обовʼязкові — тож автор без імені показував адресу
            # читачам ІНШИХ організацій. Лор-шар бере `public_display_name`.
            span { @comment.user&.public_display_name.presence || t("codex.comments.anonymous_author") }
            time(datetime: @comment.created_at.iso8601) { @comment.created_at.utc.strftime("%Y-%m-%d %H:%M UTC") }
          end

          if @comment.hidden?
            p(class: "text-tiny text-status-warning-text") { t("codex.comments.hidden") }
          else
            div(class: "prose prose-sm dark:prose-invert max-w-none text-gaia-text") do
              raw safe(Codex::MarkdownRenderer.render(@comment.body_md))
            end
          end
        end
      end

      private

      def dom_id
        "codex_comment_#{@comment.id}"
      end
    end
  end
end
