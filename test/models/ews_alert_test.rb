require "test_helper"

class EwsAlertTest < ActiveSupport::TestCase
  test "resolve! sets status and resolved_at" do
    alert = ews_alerts(:drought_alert)
    user = users(:forester_dmytro)

    alert.resolve!(user: user, notes: "Irrigation activated manually")
    alert.reload

    assert alert.status_resolved?
    assert_not_nil alert.resolved_at
    assert_equal user, alert.resolver
    assert_equal "Irrigation activated manually", alert.resolution_notes
  end

  test "coordinates returns tree coordinates when tree present" do
    alert = ews_alerts(:drought_alert)
    coords = alert.coordinates
    assert_equal [ alert.tree.latitude, alert.tree.longitude ], coords
  end

  test "actionable? returns true for critical fire" do
    alert = ews_alerts(:fire_alert)
    assert alert.actionable?
  end

  test "actionable? returns false for medium drought" do
    alert = ews_alerts(:drought_alert)
    refute alert.actionable?
  end
end
