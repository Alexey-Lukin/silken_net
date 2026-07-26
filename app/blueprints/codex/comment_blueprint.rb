# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class Codex::CommentBlueprint < Blueprinter::Base
  identifier :id

  fields :body_md, :parent_id, :flag_reason, :created_at, :updated_at

  field(:author) do |comment|
    {
      id: comment.user_id
    }
  end

  field(:hidden) { |comment| comment.hidden? }

  field :body_html do |comment|
    Codex::MarkdownRenderer.render(comment.body_md).to_s
  end

  field :replies_count do |comment|
    comment.replies.count
  end
end
