# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Codex::Fractions::ProfileBadge — compact 1-row teaser for embedding in
# the user profile. Stays inside its own gaia-* island so the legacy
# `Users::Profile` palette is not touched.
module Codex
  module Fractions
    class ProfileBadge < ApplicationComponent
      def initialize(fraction:)
        @fraction = fraction
      end

      def view_template
        div(
          class: tokens(
            "inline-flex items-center gap-3 px-3 py-2 border border-gaia-border",
            "bg-gaia-surface text-gaia-text"
          ),
          id: "codex_fraction_profile_badge"
        ) do
          span(class: "text-mini uppercase tracking-[0.3em] text-gaia-text-muted") { t("codex.fractions.label") }
          if @fraction
            span(class: "text-tiny font-mono uppercase tracking-widest") do
              @fraction.archetype_key
            end
            render Codex::Fractions::Cooldown.new(fraction: @fraction)
          else
            a(
              href: codex_fraction_picker_path,
              class: tokens(
                "text-mini uppercase tracking-[0.3em] underline",
                "hover:text-gaia-primary focus-visible:ring-2 focus-visible:ring-gaia-primary"
              )
            ) { t("codex.fractions.choose_short") }
          end
        end
      end
    end
  end
end
