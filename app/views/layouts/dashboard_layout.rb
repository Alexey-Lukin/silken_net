# frozen_string_literal: true

class DashboardLayout < ApplicationComponent
  # @param title [String] page title
  # @param current_user [User] authenticated user (passed from controller)
  # @param current_path [String] request path for nav highlighting + breadcrumbs
  # @param ews_alert_count [Integer] pre-computed unresolved alert count (eager-load in controller)
  def initialize(title:, current_user:, current_path: "/", ews_alert_count: 0)
    @title = title
    @current_user = current_user
    @current_path = current_path
    @ews_alert_count = ews_alert_count
  end

  def view_template(&block)
    doctype
    html(class: "h-full dark") do
      render_head
      body(class: "h-full font-mono antialiased bg-white text-gray-900 dark:bg-black dark:text-emerald-500 overflow-hidden transition-colors duration-300") do
        div(class: "flex h-full overflow-hidden") do
          # ЦЕНТРАЛЬНА НАВІГАЦІЯ — hidden on mobile, visible on md+
          div(class: "hidden md:block") do
            render Navigation::Sidebar.new(
              current_path: @current_path,
              ews_alert_count: @ews_alert_count
            )
          end

          # ГОЛОВНИЙ ТЕРМІНАЛ
          main(class: "flex-1 flex flex-col min-w-0 bg-gray-50 dark:bg-black relative transition-colors duration-300", role: "main") do
            # Фоновий шум (текстура Цитаделі)
            div(class: "absolute inset-0 opacity-[0.03] pointer-events-none dark:bg-[url('https://www.transparenttextures.com/patterns/carbon-fibre.png')]", aria_hidden: "true")

            render_top_bar

            div(class: "flex-1 overflow-y-auto p-4 md:p-8 custom-scrollbar relative z-10") do
              div(class: "max-w-7xl mx-auto px-4 sm:px-6 lg:px-8") do
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
    header(class: "h-16 md:h-20 border-b border-gray-200 dark:border-emerald-900/30 flex items-center justify-between px-4 md:px-8 bg-white/80 dark:bg-black/50 backdrop-blur-md z-20 transition-colors duration-300", role: "banner") do
      div(class: "flex flex-col min-w-0") do
        render_breadcrumbs
        h1(class: "text-base md:text-xl font-light tracking-[0.2em] uppercase text-gray-900 dark:text-white mt-1 truncate") { @title }
      end

      div(class: "flex items-center space-x-4 md:space-x-6") do
        render Views::Shared::UI::ThemeSwitcher.new
        render_system_telemetry
        render_user_avatar
      end
    end
  end

  def render_breadcrumbs
    nav(aria_label: "Breadcrumb", class: "flex text-[9px] uppercase tracking-widest text-gray-400 dark:text-emerald-900 font-bold") do
      ol(class: "flex items-center space-x-2") do
        li { a(href: helpers.api_v1_dashboard_index_path, class: "hover:text-gaia-primary transition-colors") { "Citadel" } }

        # Парсинг шляху для крихт — використовуємо @current_path замість helpers.request.path
        path_segments = @current_path.split("/").reject(&:empty?).drop(2) # Виключаємо api/v1

        path_segments.each_with_index do |segment, index|
          li(class: "flex items-center space-x-2") do
            span { "//" }
            span(class: index == path_segments.size - 1 ? "text-gray-600 dark:text-emerald-700" : "") { segment.humanize }
          end
        end
      end
    end
  end

  def render_system_telemetry
    div(class: "hidden md:flex items-center space-x-4 px-4 py-1.5 border border-gray-200 dark:border-emerald-900/50 bg-gray-50 dark:bg-emerald-950/10 transition-colors duration-300") do
      div(class: "flex flex-col text-right") do
        span(class: "text-[8px] text-gray-400 dark:text-emerald-800 uppercase") { "Core Sync" }
        span(class: "text-[10px] text-gray-700 dark:text-emerald-400") { "1.12 THz" }
      end
      div(class: "h-1 w-1 rounded-full bg-gaia-primary animate-pulse")
    end
  end

  def render_user_avatar
    div(class: "flex items-center space-x-3") do
      div(class: "text-right hidden lg:block") do
        p(class: "text-[10px] text-gray-900 dark:text-white leading-none") { @current_user&.full_name }
        p(class: "text-[8px] text-gray-400 dark:text-emerald-900 uppercase tracking-tighter mt-1") { @current_user&.role }
      end
      div(class: "h-10 w-10 border border-gaia-primary flex items-center justify-center text-gaia-primary bg-gray-50 dark:bg-emerald-950/20 shadow-[0_0_10px_rgba(16,185,129,0.1)] transition-colors duration-300") do
        @current_user&.first_name&.first || "A"
      end
    end
  end
end
