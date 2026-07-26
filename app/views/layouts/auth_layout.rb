# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Lightweight layout for standalone auth pages (login, forgot/reset password).
# These pages render outside the DashboardLayout since the user is not authenticated yet.
# Provides the minimal HTML document structure with CSS/JS includes.
class AuthLayout < ApplicationComponent
  include Phlex::Rails::Layout

  # @param title [String] page title
  # @param content [Phlex::HTML] page content component
  def initialize(title:, content: nil)
    @title = title
    @content = content
  end

  def view_template
    doctype
    html(class: "h-full dark", lang: I18n.locale.to_s) do
      head do
        title { "Silken Net // #{@title}" }
        meta(name: "viewport", content: "width=device-width,initial-scale=1")
        link(rel: "icon", href: "/icon.png", type: "image/png")
        link(rel: "icon", href: "/icon.svg", type: "image/svg+xml")
        link(rel: "apple-touch-icon", href: "/icon.png")
        csp_meta_tag
        csrf_meta_tags
        stylesheet_link_tag "application", "tailwind", "data-turbo-track": "reload"
        javascript_importmap_tags
      end

      body(class: "h-full font-mono antialiased bg-gaia-surface-base text-gaia-primary") do
        render @content if @content
      end
    end
  end
end
