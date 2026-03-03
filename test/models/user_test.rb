require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "full_name returns first and last name" do
    user = users(:admin_olena)
    assert_equal "Olena Kovalenko", user.full_name
  end

  test "full_name falls back to email when names blank" do
    user = users(:admin_olena)
    user.first_name = nil
    user.last_name = nil
    assert_equal user.email_address, user.full_name
  end

  test "forest_commander? returns true for admin" do
    assert users(:admin_olena).forest_commander?
  end

  test "forest_commander? returns true for forester" do
    assert users(:forester_dmytro).forest_commander?
  end

  test "forest_commander? returns false for investor" do
    refute users(:investor_maria).forest_commander?
  end

  test "email_address is normalized to downcase" do
    user = User.new(email_address: "  ADMIN@EXAMPLE.COM  ", password: "password123", role: :admin)
    user.valid?
    assert_equal "admin@example.com", user.email_address
  end

  test "touch_visit! updates last_seen_at when nil" do
    user = users(:admin_olena)
    user.update_columns(last_seen_at: nil)

    user.touch_visit!
    user.reload

    assert_not_nil user.last_seen_at
  end

  test "touch_visit! updates last_seen_at when stale (older than 5 minutes)" do
    user = users(:admin_olena)
    user.update_columns(last_seen_at: 10.minutes.ago)

    freeze_time do
      user.touch_visit!
      user.reload

      assert_in_delta Time.current, user.last_seen_at, 1.second
    end
  end

  test "touch_visit! skips update when last_seen_at is recent (within 5 minutes)" do
    user = users(:admin_olena)
    recent_time = 2.minutes.ago
    user.update_columns(last_seen_at: recent_time)

    user.touch_visit!
    user.reload

    assert_in_delta recent_time, user.last_seen_at, 1.second
  end
end
