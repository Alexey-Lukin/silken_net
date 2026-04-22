// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../StateRootAnchor.sol";

/**
 * @title StateRootAnchor Test Suite
 * @notice Comprehensive Foundry tests for StateRootAnchor — weekly L1 state finalization.
 *
 * Best practices applied:
 *  1. vm.warp for time-dependent tests (MIN_ANCHOR_INTERVAL)
 *  2. Sequential anchoring tests verify counter/mapping consistency
 *  3. Immutability tests — same root cannot be anchored twice
 *  4. Boundary tests for getRootAtIndex (0, > anchorCount)
 *  5. Event verification with all indexed/non-indexed fields
 *  6. Fuzz tests for arbitrary root values
 */
contract StateRootAnchorTest is Test {
    StateRootAnchor public anchor;

    address public admin = makeAddr("admin");
    address public oracle = makeAddr("oracle");
    address public unauthorized = makeAddr("unauthorized");

    bytes32 public constant ROOT_1 = keccak256("state-root-week-1");
    bytes32 public constant ROOT_2 = keccak256("state-root-week-2");
    bytes32 public constant ROOT_3 = keccak256("state-root-week-3");

    event StateRootStored(bytes32 indexed root, uint256 timestamp, uint256 anchorIndex);

    function setUp() public {
        anchor = new StateRootAnchor(admin, oracle);
        // Start at a reasonable timestamp
        vm.warp(1_700_000_000);
    }

    // ═══════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════

    function test_constructor_grantsRoles() public view {
        assertTrue(anchor.hasRole(anchor.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(anchor.hasRole(anchor.ANCHOR_ROLE(), oracle));
    }

    function test_constructor_initialStateIsEmpty() public view {
        assertEq(anchor.latestRoot(), bytes32(0));
        assertEq(anchor.latestTimestamp(), 0);
        assertEq(anchor.anchorCount(), 0);
        assertEq(anchor.lastAnchorTime(), 0);
    }

    function testRevert_constructor_zeroAdmin() public {
        vm.expectRevert("StateRootAnchor: zero admin");
        new StateRootAnchor(address(0), oracle);
    }

    function testRevert_constructor_zeroOracle() public {
        vm.expectRevert("StateRootAnchor: zero oracle");
        new StateRootAnchor(admin, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════

    function test_minAnchorInterval() public view {
        assertEq(anchor.MIN_ANCHOR_INTERVAL(), 6 days);
    }

    function test_anchorRoleConstant() public view {
        assertEq(anchor.ANCHOR_ROLE(), keccak256("ANCHOR_ROLE"));
    }

    // ═══════════════════════════════════════════════════════════════════
    // STORE STATE ROOT
    // ═══════════════════════════════════════════════════════════════════

    function test_storeStateRoot_firstAnchor() public {
        vm.prank(oracle);
        anchor.storeStateRoot(ROOT_1);

        assertEq(anchor.latestRoot(), ROOT_1);
        assertEq(anchor.latestTimestamp(), block.timestamp);
        assertEq(anchor.anchorCount(), 1);
        assertEq(anchor.lastAnchorTime(), block.timestamp);
        assertEq(anchor.rootTimestamps(ROOT_1), block.timestamp);
        assertEq(anchor.rootHistory(1), ROOT_1);
    }

    function test_storeStateRoot_emitsEvent() public {
        vm.prank(oracle);
        vm.expectEmit(true, false, false, true);
        emit StateRootStored(ROOT_1, block.timestamp, 1);
        anchor.storeStateRoot(ROOT_1);
    }

    function test_storeStateRoot_multipleAnchorsWithInterval() public {
        // Week 1
        vm.prank(oracle);
        anchor.storeStateRoot(ROOT_1);

        // Week 2 — warp 7 days
        vm.warp(block.timestamp + 7 days);
        vm.prank(oracle);
        anchor.storeStateRoot(ROOT_2);

        // Week 3 — warp 7 days
        vm.warp(block.timestamp + 7 days);
        vm.prank(oracle);
        anchor.storeStateRoot(ROOT_3);

        assertEq(anchor.anchorCount(), 3);
        assertEq(anchor.latestRoot(), ROOT_3);
        assertEq(anchor.rootHistory(1), ROOT_1);
        assertEq(anchor.rootHistory(2), ROOT_2);
        assertEq(anchor.rootHistory(3), ROOT_3);
    }

    function testRevert_storeStateRoot_emptyRoot() public {
        vm.prank(oracle);
        vm.expectRevert("StateRootAnchor: empty root");
        anchor.storeStateRoot(bytes32(0));
    }

    function testRevert_storeStateRoot_duplicateRoot() public {
        vm.prank(oracle);
        anchor.storeStateRoot(ROOT_1);

        vm.warp(block.timestamp + 7 days);
        vm.prank(oracle);
        vm.expectRevert("StateRootAnchor: root already anchored");
        anchor.storeStateRoot(ROOT_1);
    }

    function testRevert_storeStateRoot_tooSoon() public {
        vm.prank(oracle);
        anchor.storeStateRoot(ROOT_1);

        // Only 5 days later — less than 6 day minimum
        vm.warp(block.timestamp + 5 days);
        vm.prank(oracle);
        vm.expectRevert("StateRootAnchor: too soon since last anchor");
        anchor.storeStateRoot(ROOT_2);
    }

    function test_storeStateRoot_exactlyAtMinInterval() public {
        vm.prank(oracle);
        anchor.storeStateRoot(ROOT_1);

        // Exactly 6 days later — should succeed
        vm.warp(block.timestamp + 6 days);
        vm.prank(oracle);
        anchor.storeStateRoot(ROOT_2);

        assertEq(anchor.anchorCount(), 2);
    }

    function testRevert_storeStateRoot_unauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        anchor.storeStateRoot(ROOT_1);
    }

    // ═══════════════════════════════════════════════════════════════════
    // IS ROOT ANCHORED
    // ═══════════════════════════════════════════════════════════════════

    function test_isRootAnchored_true() public {
        vm.prank(oracle);
        anchor.storeStateRoot(ROOT_1);

        assertTrue(anchor.isRootAnchored(ROOT_1));
    }

    function test_isRootAnchored_false() public view {
        assertFalse(anchor.isRootAnchored(ROOT_1));
    }

    // ═══════════════════════════════════════════════════════════════════
    // GET ROOT AT INDEX
    // ═══════════════════════════════════════════════════════════════════

    function test_getRootAtIndex_returnsCorrectData() public {
        vm.prank(oracle);
        anchor.storeStateRoot(ROOT_1);

        (bytes32 root, uint256 ts) = anchor.getRootAtIndex(1);
        assertEq(root, ROOT_1);
        assertEq(ts, block.timestamp);
    }

    function testRevert_getRootAtIndex_zeroIndex() public {
        vm.expectRevert("StateRootAnchor: invalid index");
        anchor.getRootAtIndex(0);
    }

    function testRevert_getRootAtIndex_beyondCount() public {
        vm.prank(oracle);
        anchor.storeStateRoot(ROOT_1);

        vm.expectRevert("StateRootAnchor: invalid index");
        anchor.getRootAtIndex(2);
    }

    function testRevert_getRootAtIndex_noAnchors() public {
        vm.expectRevert("StateRootAnchor: invalid index");
        anchor.getRootAtIndex(1);
    }

    // ═══════════════════════════════════════════════════════════════════
    // ADMIN PROTECTION
    // ═══════════════════════════════════════════════════════════════════

    function testRevert_cannotRemoveLastAdmin() public {
        bytes32 adminRole = anchor.DEFAULT_ADMIN_ROLE();
        vm.prank(admin);
        vm.expectRevert("StateRootAnchor: cannot remove last admin");
        anchor.renounceRole(adminRole, admin);
    }

    function test_canRemoveAdminIfMultiple() public {
        bytes32 adminRole = anchor.DEFAULT_ADMIN_ROLE();
        address admin2 = makeAddr("admin2");
        vm.prank(admin);
        anchor.grantRole(adminRole, admin2);

        vm.prank(admin);
        anchor.renounceRole(adminRole, admin);

        assertFalse(anchor.hasRole(adminRole, admin));
        assertTrue(anchor.hasRole(adminRole, admin2));
    }

    // ═══════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════

    function testFuzz_storeStateRoot_arbitraryRoot(bytes32 root) public {
        vm.assume(root != bytes32(0));
        vm.prank(oracle);
        anchor.storeStateRoot(root);
        assertTrue(anchor.isRootAnchored(root));
        assertEq(anchor.latestRoot(), root);
    }

    function testFuzz_multipleAnchors_counterIncrementsCorrectly(uint8 count) public {
        count = uint8(bound(uint256(count), 1, 20));

        for (uint8 i = 0; i < count; i++) {
            bytes32 root = keccak256(abi.encodePacked("root-", i));
            vm.warp(block.timestamp + 7 days);
            vm.prank(oracle);
            anchor.storeStateRoot(root);
        }

        assertEq(anchor.anchorCount(), count);
    }
}
