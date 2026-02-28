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
end
