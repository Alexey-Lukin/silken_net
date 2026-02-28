# frozen_string_literal: true

module Views
  module Layouts
    class DashboardLayout < ApplicationComponent
      def initialize(title:, current_user:)
        @title = title
        @current_user = current_user
      end

      def view_template(&block)
        doctype
        html(class: "h-full bg-black") do
          render_head
          body(class: "h-full font-sans antialiased text-emerald-500") do
            div(class: "flex h-full") do
              render Views::Components::Navigation::Sidebar.new(user: @current_user)
              
              main(class: "flex-1 overflow-y-auto p-8 bg-zinc-950") do
                header_section
                div(class: "mt-8", &block)
              end
            end
          end
        end
      end

      private

      def render_head
        head do
          title { "Silken Net // #{@title}" }
          meta(name: "viewport", content: "width=device-width,initial-scale=1")
          csp_meta_tag
          csrf_meta_tags
          stylesheet_link_tag "tailwind", "inter-font", "data-turbo-track": "reload"
          javascript_importmap_tags
        end
      end

      def header_section
        div(class: "flex justify-between items-center border-b border-emerald-900 pb-4") do
          h1(class: "text-2xl font-light tracking-widest uppercase") { @title }
          div(class: "flex items-center space-x-4") do
            span(class: "text-xs font-mono text-emerald-800") { "System Status: Nominal" }
            div(class: "h-2 w-2 rounded-full bg-emerald-500 animate-pulse")
          end
        end
      end
    end
  end
end
