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
          body(class: "h-full font-mono antialiased text-emerald-500 overflow-hidden") do
            div(class: "flex h-full overflow-hidden") do
              # ЦЕНТРАЛЬНА НАВІГАЦІЯ
              render Views::Components::Navigation::Sidebar.new
              
              # ГОЛОВНИЙ ТЕРМІНАЛ
              main(class: "flex-1 flex flex-col min-w-0 bg-black relative") do
                # Фоновий шум (текстура Цитаделі)
                div(class: "absolute inset-0 opacity-[0.03] pointer-events-none bg-[url('https://www.transparenttextures.com/patterns/carbon-fibre.png')]")
                
                render_top_bar
                
                div(class: "flex-1 overflow-y-auto p-8 custom-scrollbar relative z-10") do
                  div(class: "max-w-7xl mx-auto") do
                    yield
                  end
                end
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
          stylesheet_link_tag "application", "tailwind", "data-turbo-track": "reload"
          javascript_importmap_tags
        end
      end

      def render_top_bar
        header(class: "h-20 border-b border-emerald-900/30 flex items-center justify-between px-8 bg-black/50 backdrop-blur-md z-20") do
          div(class: "flex flex-col") do
            render_breadcrumbs
            h1(class: "text-xl font-light tracking-[0.2em] uppercase text-white mt-1") { @title }
          end

          div(class: "flex items-center space-x-6") do
            render_system_telemetry
            render_user_avatar
          end
        end
      end

      def render_breadcrumbs
        nav(class: "flex text-[9px] uppercase tracking-widest text-emerald-900 font-bold") do
          ol(class: "flex items-center space-x-2") do
            li { a(href: helpers.api_v1_dashboard_index_path, class: "hover:text-emerald-500 transition-colors") { "Citadel" } }
            
            # Автоматичний парсинг шляху для крихт
            path_segments = helpers.request.path.split('/').reject(&:empty?).drop(2) # Виключаємо api/v1
            
            path_segments.each_with_index do |segment, index|
              li(class: "flex items-center space-x-2") do
                span { "//" }
                span(class: index == path_segments.size - 1 ? "text-emerald-700" : "") { segment.humanize }
              end
            end
          end
        end
      end

      def render_system_telemetry
        div(class: "hidden md:flex items-center space-x-4 px-4 py-1.5 border border-emerald-900/50 bg-emerald-950/10") do
          div(class: "flex flex-col text-right") do
            span(class: "text-[8px] text-emerald-800 uppercase") { "Core Sync" }
            span(class: "text-[10px] text-emerald-400") { "1.12 THz" }
          end
          div(class: "h-1 w-1 rounded-full bg-emerald-500 animate-pulse")
        end
      end

      def render_user_avatar
        div(class: "flex items-center space-x-3") do
          div(class: "text-right hidden lg:block") do
            p(class: "text-[10px] text-white leading-none") { @current_user&.full_name }
            p(class: "text-[8px] text-emerald-900 uppercase tracking-tighter mt-1") { @current_user&.role }
          end
          div(class: "h-10 w-10 border border-emerald-500 flex items-center justify-center text-emerald-500 bg-emerald-950/20 shadow-[0_0_10px_rgba(16,185,129,0.1)]") do
            @current_user&.first_name&.first || "A"
          end
        end
      end
    end
  end
end
