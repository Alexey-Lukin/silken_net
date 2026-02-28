require "test_helper"
require_relative "../../app/services/attractor"

class SilkenNet::AttractorTest < ActiveSupport::TestCase
  test "calculate_z is deterministic for same inputs" do
    z1 = SilkenNet::Attractor.calculate_z(12345, 22.0, 5)
    z2 = SilkenNet::Attractor.calculate_z(12345, 22.0, 5)
    assert_equal z1, z2
  end

  test "calculate_z returns different values for different seeds" do
    z1 = SilkenNet::Attractor.calculate_z(12345, 22.0, 5)
    z2 = SilkenNet::Attractor.calculate_z(67890, 22.0, 5)
    refute_equal z1, z2
  end

  test "calculate_z returns a finite float" do
    z = SilkenNet::Attractor.calculate_z(42, 20.0, 3)
    assert z.is_a?(Float)
    assert z.finite?
  end

  test "homeostatic? returns true when z within bounds" do
    family = tree_families(:scots_pine)
    z = (family.critical_z_min + family.critical_z_max) / 2.0
    assert SilkenNet::Attractor.homeostatic?(z, family)
  end

  test "homeostatic? returns false when z below min" do
    family = tree_families(:scots_pine)
    refute SilkenNet::Attractor.homeostatic?(family.critical_z_min - 1.0, family)
  end

  test "homeostatic? returns false when z above max" do
    family = tree_families(:scots_pine)
    refute SilkenNet::Attractor.homeostatic?(family.critical_z_max + 1.0, family)
  end

  test "generate_trajectory returns array of 250 points" do
    trajectory = SilkenNet::Attractor.generate_trajectory(42, 20.0, 3)
    assert_equal 250, trajectory.length
  end

  test "generate_trajectory points have x y z keys" do
    trajectory = SilkenNet::Attractor.generate_trajectory(42, 20.0, 3)
    point = trajectory.first
    assert point.key?(:x)
    assert point.key?(:y)
    assert point.key?(:z)
  end

  test "generate_trajectory last z matches calculate_z" do
    seed, temp, acoustic = 42, 20.0, 3
    z = SilkenNet::Attractor.calculate_z(seed, temp, acoustic)
    trajectory = SilkenNet::Attractor.generate_trajectory(seed, temp, acoustic)
    assert_equal z, trajectory.last[:z]
  end
end
