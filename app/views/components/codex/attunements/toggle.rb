# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::Attunement::Toggle — single button reflecting whether the current
# user is currently attuned to the host node.
#
# 🔴 The counter is NOT live, and the previous docstring's claim that it was
# is the reason this note is long. It promised a "Turbo Stream channel
# published by Codex::AttunementBroadcastWorker" — but that worker used raw
# `ActionCable.server.broadcast`, not Turbo; nothing ever subscribed; and the
# same commit that wrote the promise DELETED the Stimulus fallback that had
# actually worked, on the strength of the promise. The worker was removed
# 2026-07-27 (UI.2 descope). The count you see is the one the controller
# passed in at render time; it refreshes on reload.
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
          )
        ) do
          div(class: "space-y-0.5") do
            p(class: "text-mini uppercase tracking-[0.3em] text-gaia-text-muted") { t("codex.attunements.title") }
            p(class: "text-tiny text-gaia-text-muted font-mono", id: dom_count_id) { @count.to_s }
          end

          # ДВІ дії — ДВА маршрути. Attune і un-attune не ділять адресу: колекційний
          # шлях зареєстровано лише під POST, а зняття живе окремим `attunements/me`.
          # `button_to` тут не стиль, а три виправлення разом: він бере ціль з гілки,
          # кладе `authenticity_token` (рукописна `<form>` його не мала, тож без JS
          # гілка attune падала на CSRF) і робить валідний `method="post"` + `_method`
          # (`method="delete"` на `<form>` — невалідне значення, браузер відкочується в GET).
          button_to(
            @attuned ? t("codex.attunements.attuned") : t("codex.attunements.attune"),
            @attuned ? codex_node_my_attunement_path(@node.slug) : codex_node_attunements_path(@node.slug),
            method: @attuned ? :delete : :post,
            class: tokens(
              "inline-flex items-center gap-2 px-3 py-1 border text-tiny uppercase tracking-[0.3em]",
              "focus-visible:ring-2 focus-visible:ring-gaia-primary",
              button_state_classes
            )
          )
        end
      end

      private

      def button_state_classes
        if @attuned
          "bg-status-success text-status-success-text border-status-success"
        else
          "bg-gaia-surface-sunken text-gaia-text border-gaia-border hover:bg-gaia-primary hover:text-gaia-primary-text"
        end
      end

      def dom_count_id
        "codex_node_#{@node.id}_attunement_count"
      end
    end
  end
end
