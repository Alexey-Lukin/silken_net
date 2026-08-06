# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::Comments::Form — minimal composer for `body_md`. Posts to the
# nested `comments#create` endpoint. JS form-reset on Turbo Stream
# response is handled by the `codex--comment` Stimulus controller.
module Codex
  module Comments
    class Form < ApplicationComponent
      def initialize(node:)
        @node = node
      end

      def view_template
        # [UI.7] `form_with`, не рукописна `<form>`: та не несла `authenticity_token`,
        # тож без JS сабміт давав 422 — працювало лише тому, що Turbo підставляє
        # `X-CSRF-Token` зі свого мета-тега. Тіло лишається дослівним: контракт із
        # `codex--comment`-контролером тримається на `data`-таргеті САМЕ на `<form>`.
        form_with(
          url: codex_node_comments_path(@node.slug),
          method: :post,
          class: "space-y-2",
          data: { "codex--comment-target": "form" }
        ) do
          textarea(
            name: "comment[body_md]",
            rows: 3,
            required: true,
            placeholder: t("codex.comments.placeholder"),
            maxlength: ::Codex::Comment::BODY_MAX,
            class: tokens(
              "w-full p-2 border border-gaia-input-border bg-gaia-input-bg text-gaia-input-text",
              "font-mono text-tiny",
              "focus-visible:ring-2 focus-visible:ring-gaia-primary"
            ),
            data: { "codex--comment-target": "body" }
          )
          div(class: "flex justify-end") do
            button(
              type: "submit",
              class: tokens(
                "inline-flex items-center gap-2 px-3 py-1 border",
                "bg-gaia-primary text-gaia-primary-text border-gaia-primary",
                "focus-visible:ring-2 focus-visible:ring-gaia-primary"
              )
            ) do
              span(class: "text-tiny uppercase tracking-[0.3em]") { t("codex.comments.post") }
            end
          end
        end
      end
    end
  end
end
