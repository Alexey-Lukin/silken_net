# frozen_string_literal: true

# @label Navigation Sidebar
# @display bg_color "#000"
class SidebarPreview < Lookbook::Preview
  # @label Default (Dashboard Active)
  # @notes Sidebar with the root dashboard path active.
  def default
    render Navigation::Sidebar.new(current_path: "/api/v1/dashboard", ews_alert_count: 0)
  end

  # @label With Alert Badge
  # @notes Shows 7 unresolved threat alerts in the sidebar badge.
  def with_alerts
    render Navigation::Sidebar.new(current_path: "/api/v1/alerts", ews_alert_count: 7)
  end

  # @label Telemetry Active
  # @notes Neural Network section highlighted with live telemetry active.
  def telemetry_active
    render Navigation::Sidebar.new(current_path: "/api/v1/telemetry/live", ews_alert_count: 0)
  end

  # @label Interactive
  # @param current_path text "Current request path for active-nav highlighting"
  # @param ews_alert_count range { min: 0, max: 99, step: 1 }
  def interactive(current_path: "/api/v1/dashboard", ews_alert_count: 0)
    render Navigation::Sidebar.new(current_path: current_path, ews_alert_count: ews_alert_count.to_i)
  end
end
