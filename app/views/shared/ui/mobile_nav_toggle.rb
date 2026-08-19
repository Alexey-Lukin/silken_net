# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Views
  module Shared
    module UI
      # Mobile-only hamburger button that opens the off-canvas Sidebar drawer.
      #
      # The drawer itself is a native `<dialog>` element rendered by the
      # `DashboardLayout`. Opening it goes through the `mobile-nav` Stimulus
      # controller (a thin shim that calls `dialog.showModal()`) — once the
      # dialog is open, the browser handles focus-trap, Escape-to-close, the
      # top-layer stacking, and the `::backdrop` pseudo-element natively.
      #
      # Renders a real <button> so it inherits keyboard-activation semantics
      # for free.
      class MobileNavToggle < ApplicationComponent
        # @param target_id [String] DOM id of the <dialog> drawer element this toggle controls
        def initialize(target_id: "mobile-nav-drawer")
          @target_id = target_id
        end

        def view_template
          button(
            type: "button",
            data: { action: "click->mobile-nav#open" },
            aria_controls: @target_id,
            aria_expanded: "false",
            aria_label: t("accessibility.open_navigation"),
            class: tokens(
              "md:hidden inline-flex items-center justify-center",
              "h-10 w-10 -ml-2",
              "border border-gaia-border text-gaia-text-muted",
              "hover:text-gaia-primary-strong hover:border-gaia-primary",
              "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong",
              "transition-colors duration-200"
            )
          ) do
            burger_icon
          end
        end

        private

        def burger_icon
          svg(
            xmlns: "http://www.w3.org/2000/svg",
            class: "h-5 w-5",
            fill: "none",
            viewBox: "0 0 24 24",
            stroke: "currentColor",
            stroke_width: "2",
            aria_hidden: "true"
          ) do |s|
            s.path(stroke_linecap: "round", stroke_linejoin: "round", d: "M4 6h16M4 12h16M4 18h16")
          end
        end
      end
    end
  end
end
