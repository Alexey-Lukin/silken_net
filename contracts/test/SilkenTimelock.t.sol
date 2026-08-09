// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "forge-std/Test.sol";
import "../SilkenTimelock.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title SilkenTimelock Test Suite
 * @notice Foundry tests for SilkenTimelock.sol — 48h governance timelock.
 * @dev Covers: MIN_DELAY_HOURS constant, constructor minDelay, role setup,
 *      scheduling operations with delay enforcement.
 */
contract SilkenTimelockTest is Test {
    SilkenTimelock public timelock;

    address public governor = makeAddr("governor");
    address public executor = makeAddr("executor");
    address public timelockAdmin = makeAddr("timelockAdmin");

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
        address target = makeAddr("scheduleTarget");
        bytes memory data = abi.encodeWithSignature("doSomething()");
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("test-salt");
        uint256 tooShortDelay = 1 hours; // Less than 48h

        uint256 minDelay = timelock.getMinDelay(); // pre-compute: an external call in the args eats the prank
        vm.prank(governor);
        vm.expectRevert(
            abi.encodeWithSelector(TimelockController.TimelockInsufficientDelay.selector, tooShortDelay, minDelay)
        );
        timelock.schedule(target, 0, data, predecessor, salt, tooShortDelay);
    }

    function test_schedule_acceptsMinDelay() public {
        address target = makeAddr("scheduleTarget");
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
        address target = makeAddr("scheduleTarget");
        bytes memory data = abi.encodeWithSignature("doSomething()");
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("unauth-salt");

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        vm.prank(executor); // executor has EXECUTOR_ROLE, not PROPOSER_ROLE
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, executor, proposerRole)
        );
        timelock.schedule(target, 0, data, predecessor, salt, 48 hours);
    }

    // ─── Execute with Delay ───────────────────────────────────────────

    function test_execute_cannotRunBeforeDelay() public {
        address target = makeAddr("scheduleTarget");
        bytes memory data = abi.encodeWithSignature("doSomething()");
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("exec-test");

        vm.prank(governor);
        timelock.schedule(target, 0, data, predecessor, salt, 48 hours);

        // Try executing immediately — should fail (not ready yet).
        // expectPartialRevert: TimelockUnexpectedOperationState carries the operation id AND an
        // internal state-bitmap, so only the selector is a stable subject to assert on.
        vm.prank(executor);
        vm.expectPartialRevert(TimelockController.TimelockUnexpectedOperationState.selector);
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
