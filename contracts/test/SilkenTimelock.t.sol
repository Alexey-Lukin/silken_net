// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "forge-std/Test.sol";
import "../SilkenTimelock.sol";

/**
 * @title SilkenTimelock Test Suite
 * @notice Foundry tests for SilkenTimelock.sol — 48h governance timelock.
 * @dev Covers: MIN_DELAY_HOURS constant, constructor minDelay, role setup,
 *      scheduling operations with delay enforcement.
 */
contract SilkenTimelockTest is Test {
    SilkenTimelock public timelock;

    address public governor = address(0xA);
    address public executor = address(0xB);
    address public timelockAdmin = address(0xC);

    function setUp() public {
        address[] memory proposers = new address[](1);
        proposers[0] = governor;

        address[] memory executors = new address[](1);
        executors[0] = executor;

        timelock = new SilkenTimelock(proposers, executors, timelockAdmin);
    }

    // ─── Constants ────────────────────────────────────────────────────

    function test_minDelayHoursIs48() public view {
        assertEq(timelock.MIN_DELAY_HOURS(), 48);
    }

    function test_minDelayIs48Hours() public view {
        // minDelay = MIN_DELAY_HOURS * 1 hours = 48 * 3600 = 172800 seconds
        assertEq(timelock.getMinDelay(), 48 * 1 hours);
        assertEq(timelock.getMinDelay(), 172800);
    }

    // ─── Roles ────────────────────────────────────────────────────────

    function test_governorHasProposerRole() public view {
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), governor));
    }

    function test_executorHasExecutorRole() public view {
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), executor));
    }

    function test_adminHasTimelockAdminRole() public view {
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), timelockAdmin));
    }

    function test_governorAlsoHasCancellerRole() public view {
        // OpenZeppelin TimelockController grants CANCELLER_ROLE to proposers
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), governor));
    }

    // ─── Scheduling Operations ────────────────────────────────────────

    function test_schedule_enforcesMinDelay() public {
        address target = address(0xDEAD);
        bytes memory data = abi.encodeWithSignature("doSomething()");
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("test-salt");
        uint256 tooShortDelay = 1 hours; // Less than 48h

        vm.prank(governor);
        vm.expectRevert(); // TimelockController: insufficient delay
        timelock.schedule(target, 0, data, predecessor, salt, tooShortDelay);
    }

    function test_schedule_acceptsMinDelay() public {
        address target = address(0xDEAD);
        bytes memory data = abi.encodeWithSignature("doSomething()");
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("test-salt-ok");
        uint256 delay = 48 hours;

        vm.prank(governor);
        timelock.schedule(target, 0, data, predecessor, salt, delay);

        bytes32 opId = timelock.hashOperation(target, 0, data, predecessor, salt);
        assertTrue(timelock.isOperationPending(opId));
    }

    function test_schedule_revertsForNonProposer() public {
        address target = address(0xDEAD);
        bytes memory data = abi.encodeWithSignature("doSomething()");
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("unauth-salt");

        vm.prank(executor); // executor has EXECUTOR_ROLE, not PROPOSER_ROLE
        vm.expectRevert();
        timelock.schedule(target, 0, data, predecessor, salt, 48 hours);
    }

    // ─── Execute with Delay ───────────────────────────────────────────

    function test_execute_cannotRunBeforeDelay() public {
        address target = address(0xDEAD);
        bytes memory data = abi.encodeWithSignature("doSomething()");
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("exec-test");

        vm.prank(governor);
        timelock.schedule(target, 0, data, predecessor, salt, 48 hours);

        // Try executing immediately — should fail (not ready yet)
        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(target, 0, data, predecessor, salt);
    }

    function test_execute_succeedsAfterDelay() public {
        // Deploy a simple target contract that records calls
        MockTarget mockTarget = new MockTarget();
        bytes memory data = abi.encodeWithSignature("ping()");
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("exec-after-delay");

        vm.prank(governor);
        timelock.schedule(address(mockTarget), 0, data, predecessor, salt, 48 hours);

        // Warp time forward by 48 hours
        vm.warp(block.timestamp + 48 hours);

        vm.prank(executor);
        timelock.execute(address(mockTarget), 0, data, predecessor, salt);

        assertTrue(mockTarget.pinged());
    }
}

/// @dev Simple mock contract for testing timelock execution.
contract MockTarget {
    bool public pinged;

    function ping() external {
        pinged = true;
    }
}
