# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::NodeCard — Phlex card adapter around lore Codex::Node entries.
#
# Reuses dashboard tokens (gaia-* / status-*) only. The realm accent is
# pulled from `node.realm.accent_token` through the model's one home
# (`Codex::Realm#accent_border_class` / `#accent_text_class`) and applied to
# the corner badge — same maps `Codex::Citations::Pill` consumes, never a copy.
#
# Used inside `Codex::Index` grid and (Phase 4) the Battle Arena.
module Codex
  class NodeCard < ApplicationComponent
    def initialize(node:)
      @node = node
    end

    def view_template
      a(
        href: codex_node_path(@node),
        aria_label: t(".aria_label", title: @node.title_en),
        class: tokens(card_classes)
      ) do
        div(class: "relative") do
          render_cover
          render_realm_pill
          render_lifecycle_badge
        end
        div(class: "p-4 space-y-1") do
          p(class: "text-mini uppercase tracking-[0.3em] text-gaia-text-muted") { @node.codex_uid }
          h3(class: "text-base text-gaia-text font-light") { @node.title_uk }
          p(class: "text-tiny text-gaia-text-muted") { @node.title_en }
          if @node.subtitle_en.present?
            p(class: "text-mini text-gaia-primary uppercase tracking-widest") { @node.subtitle_en }
          end
        end
        render_footer
      end
    end

    private

    # NB: every `@node.realm` / `@node.realm&.` guard below (render_cover,
    # render_realm_pill, glyph_for_realm) is model-validation-dead, not real:
    # `Node#realm` is a required belongs_to and `codex_realm_id` has no
    # cascade/nullify path (plain FK, no `ON DELETE`; Realm also uses
    # `dependent: :restrict_with_error` on its `has_many :nodes`) — a Realm
    # can never be removed out from under a Node, so `.realm` is always
    # present here. Left as `&.`/`unless` for defensive style, not tested.
    def card_classes
      "block group border border-gaia-border bg-gaia-surface " \
        "shadow-sm dark:shadow-none overflow-hidden " \
        "hover:border-gaia-primary transition-all duration-200 ease-in-out " \
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary"
    end

    def render_cover
      div(class: "relative aspect-[4/3] bg-gaia-surface-sunken overflow-hidden") do
        if @node.cover_image.attached? && @node.cover_image.representable?
          img(
            src: rails_representation_path(@node.cover_image.variant(resize_to_fill: [ 480, 360 ])),
            alt: @node.title_en,
            loading: "lazy",
            class: "w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
          )
        else
          div(class: "w-full h-full flex items-center justify-center text-4xl text-gaia-primary opacity-30") do
            plain glyph_for_realm(@node.realm&.glyph)
          end
        end
      end
    end

    # [UI.10] Акцент реалму задротовано (присуд власника 2026-08-14) — доти
    # докстрінг обіцяв його, а метод зашивав один токен на всі чотири реалми,
    # тож Atlas-грід не розрізняв їх візуально взагалі.
    #
    # 🔴 Поверхня змінена з `bg-black/70` НЕ з естетики: скрим тема-інваріантний,
    # а обидві акцент-родини з темою фліпаються, тож на ньому AA недосяжна за
    # побудовою. Заразом знято приховану ваду попереднього стану — виміряно
    # (`lib/silken_net/contrast.rb`): `text-gaia-primary` на `bg-black/70` дає
    # 8.28:1 над темною обкладинкою й лише 3.36:1 над світлою, тобто читабельність
    # залежала від картинки. Суцільна тема-поверхня робить число детермінованим:
    # 7.09–17.00:1 на всіх чотирьох комбінаціях реалм × тема.
    def render_realm_pill
      return unless @node.realm

      span(class: tokens(
        "absolute top-2 left-2 px-2 py-0.5 text-micro uppercase tracking-widest font-bold",
        "bg-gaia-surface border-l-2",
        @node.realm.accent_border_class,
        @node.realm.accent_text_class
      )) { @node.realm.name_en }
    end

    def render_lifecycle_badge
      div(class: "absolute top-2 right-2") do
        render Views::Shared::UI::StatusBadge.new(status: @node.lifecycle_status)
      end
    end

    def render_footer
      div(class: "px-4 py-2 border-t border-gaia-border flex justify-between text-mini text-gaia-text-muted font-mono") do
        span { t(".elo", value: @node.attunement_elo) }
        if @node.geo_region.present?
          span(class: "truncate") { @node.geo_region }
        else
          span { t(".no_region") }
        end
      end
    end

    def glyph_for_realm(_key)
      # Deprecated wrapper — superseded by `Codex::Realm#display_glyph` which
      # is the SSOT for keyword-to-glyph mapping. Kept as a thin shim for
      # backwards compat with any external caller; new code should use
      # `node.realm&.display_glyph`.
      @node.realm&.display_glyph || ::Codex::Realm::DEFAULT_DISPLAY_GLYPH
    end
  end
end
