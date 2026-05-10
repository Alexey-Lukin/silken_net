# frozen_string_literal: true

# Codex::Fractions::OnboardingWizard — first-login banner that nudges newly
# onboarded users towards picking a Codex archetype (a "fraction"). Rendered
# by `DashboardLayout` *only* when the authenticated user has no
# `Codex::Fraction` row yet — selecting one flips this off permanently.
#
# Server-rendered, no Stimulus, no JS — clicking the CTA is a plain
# Turbo-Drive navigation to `GET /api/v1/codex/fractions/picker`. This keeps
# the wizard within ADR-CDX-4 (Codex never blocks the hot path) and matches
# the Phase-8 Stimulus audit (`docs/04_05_Codex_Lore_Module.md` § 3.1) which
# explicitly removed `codex--fraction-picker` in favour of native
# `data-turbo-confirm` / `<a>` navigation.
#
# Tokens: gaia-* / status-* only — no raw `bg-emerald-*`, `bg-white`,
# `text-gray-*` (matches `docs/04_04` § 4 § 6.4 SSOT).
module Codex
  module Fractions
    class OnboardingWizard < ApplicationComponent
      # @param current_user [User] authenticated user (used only for the
      #   addressed copy; component renders nothing when nil).
      def initialize(current_user:)
        @current_user = current_user
      end

      def view_template
        return unless @current_user

        section(
          id: "codex_onboarding_wizard",
          role: "region",
          aria_label: "Codex onboarding",
          class: tokens(
            "border border-gaia-border bg-gaia-surface text-gaia-text",
            "px-4 py-4 md:px-6 md:py-5 mb-6 md:mb-8",
            "flex flex-col gap-4 md:flex-row md:items-center md:justify-between"
          )
        ) do
          render_message
          render_actions
        end
      end

      private

      def render_message
        div(class: "space-y-1") do
          p(class: "text-mini uppercase tracking-[0.3em] text-gaia-text-muted") do
            "Codex // Onboarding"
          end
          h2(class: "text-base md:text-lg font-light tracking-wide text-gaia-text") do
            greeting
          end
          p(class: "text-tiny text-gaia-text-muted max-w-2xl") do
            "Align your account with a Codex archetype to unlock the lore layer, " \
              "join the Battle Arena, and reveal Discoveries as your forest grows."
          end
        end
      end

      def render_actions
        div(class: "flex items-center gap-3 shrink-0") do
          a(
            href: api_v1_codex_fraction_picker_path,
            class: tokens(
              "inline-flex items-center gap-2 px-4 py-2 border border-gaia-primary",
              "bg-gaia-primary text-gaia-primary-text",
              "text-tiny uppercase tracking-[0.3em]",
              "hover:bg-gaia-surface hover:text-gaia-primary",
              "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary"
            )
          ) { "Choose your Fraction →" }

          a(
            href: api_v1_codex_realms_path,
            class: tokens(
              "inline-flex items-center gap-2 px-3 py-2 border border-gaia-border",
              "text-tiny uppercase tracking-[0.3em] text-gaia-text-muted",
              "hover:text-gaia-text hover:border-gaia-primary",
              "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary"
            )
          ) { "Browse the Codex" }
        end
      end

      def greeting
        first = @current_user.first_name.to_s.strip
        if first.empty?
          "Welcome to the Codex."
        else
          "Welcome to the Codex, #{first}."
        end
      end
    end
  end
end
