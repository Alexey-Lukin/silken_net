# frozen_string_literal: true

# Codex::Comments::Item — single comment row, used inside `Codex::Comments::Thread`
# and as the broadcast target for `codex_node_<id>_comments` Turbo streams.
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
            span { @comment.user&.email_address.to_s }
            time(datetime: @comment.created_at.iso8601) { @comment.created_at.utc.strftime("%Y-%m-%d %H:%M UTC") }
          end

          if @comment.hidden?
            p(class: "text-tiny text-status-warning-text") { "Hidden by moderator." }
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
