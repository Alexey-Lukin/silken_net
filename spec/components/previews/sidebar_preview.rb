# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# @label Navigation Sidebar
# @display bg_color "#000"
class SidebarPreview < Lookbook::Preview
  # @label Default (Dashboard Active)
  # @notes Sidebar with the root dashboard path active.
  def default
    render Navigation::Sidebar.new(current_path: "/dashboard", ews_alert_count: 0,
                                   current_user: full_access_actor)
  end

  # @label With Alert Badge
  # @notes Shows 7 unresolved threat alerts in the sidebar badge.
  def with_alerts
    render Navigation::Sidebar.new(current_path: "/alerts", ews_alert_count: 7,
                                   current_user: full_access_actor)
  end

  # @label Telemetry Active
  # @notes Neural Network section highlighted with live telemetry active.
  def telemetry_active
    render Navigation::Sidebar.new(current_path: "/telemetry/live", ews_alert_count: 0,
                                   current_user: full_access_actor)
  end

  # @label Interactive
  # @param current_path text "Current request path for active-nav highlighting"
  # @param ews_alert_count range { min: 0, max: 99, step: 1 }
  def interactive(current_path: "/dashboard", ews_alert_count: 0)
    render Navigation::Sidebar.new(current_path: current_path, ews_alert_count: ews_alert_count.to_i,
                                   current_user: full_access_actor)
  end

  private

  # [UI.5] Пункти меню роле-гейтовані, а прев'ю сесії не має — без актора Lookbook
  # показував би звужене меню, і компонент читався б як зламаний. Незбережений
  # запис достатній: фільтр питає лише предикат ролі, не БД.
  def full_access_actor
    User.new(role: :super_admin)
  end
end
