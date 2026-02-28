require "test_helper"

class TreeTest < ActiveSupport::TestCase
  test "creates wallet after creation" do
    tree = Tree.create!(
      did: "SNET-NEWTEST01",
      tree_family: tree_families(:scots_pine),
      latitude: 49.43,
      longitude: 32.06
    )
    assert tree.wallet.present?
    assert_equal 0, tree.wallet.balance
  end

  test "DID is normalized to uppercase" do
    tree = Tree.new(did: "snet-lowercase1", tree_family: tree_families(:scots_pine))
    tree.valid?
    assert_equal "SNET-LOWERCASE1", tree.did
  end

  test "mark_seen! updates last_seen_at" do
    tree = trees(:pine_alpha)
    assert_nil tree.last_seen_at
    tree.mark_seen!
    tree.reload
    assert_not_nil tree.last_seen_at
    assert_in_delta Time.current, tree.last_seen_at, 2.seconds
  end
end
