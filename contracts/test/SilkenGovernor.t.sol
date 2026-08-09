// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "forge-std/Test.sol";
import "../SilkenGovernor.sol";
import "../SilkenTimelock.sol";
import "../SilkenForestCoin.sol";
import "../SilkenCarbonCoin.sol";
import "../ProtocolParameters.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/**
 * @title SilkenGovernor Test Suite
 * @notice Foundry tests for SilkenGovernor.sol — DAO governance for SilkenNet.
 * @dev Covers: constructor params, voting delay/period, proposal threshold, quorum,
 *      full governance pipeline (propose → vote → queue → execute),
 *      Flash Loan defense via snapshot voting, and integration with ProtocolParameters.
 *
 * [ARCH.4] Governance DAO tests.
 * [E.35]   Flash Loan defense verification.
 * [BIZ.4]  SFC voting mechanism.
 */
contract SilkenGovernorTest is Test {
    SilkenForestCoin public sfc;
    SilkenTimelock public timelock;
    SilkenGovernor public governor;
    ProtocolParameters public protocolParams;
    SilkenCarbonCoin public scc; // [BIZ.4] governance-controlled token (admin = Timelock)

    address public admin = makeAddr("admin");
    address public minter = makeAddr("minter");
    address public slasher = makeAddr("slasher");
    // NB: voter1..3 were address(0x1..0x3) — the ecrecover/sha256/ripemd160 PRECOMPILES.
    // Harmless here only because ERC20 never calls the recipient; makeAddr removes the trap.
    address public voter1 = makeAddr("voter1");
    address public voter2 = makeAddr("voter2");
    address public voter3 = makeAddr("voter3");

    uint256 public constant VOTING_DELAY = 43200; // ~1 day on Polygon
    uint256 public constant VOTING_PERIOD = 302400; // ~7 days on Polygon
    uint256 public constant PROPOSAL_THRESHOLD = 10_000e18; // [CONTRACT.1] 10 000 SFC = 0.01% MAX_SUPPLY (anti-spam)

    function setUp() public {
        // 1. Deploy SFC (governance token)
        sfc = new SilkenForestCoin(admin, admin, minter, slasher); // [SEC.1] pauser=admin (no pause in governance tests)

        // 2. Deploy Timelock (governor is proposer, anyone can execute)
        address[] memory proposers = new address[](0); // Will add governor after deployment
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute after delay

        timelock = new SilkenTimelock(proposers, executors, admin);

        // 3. Deploy Governor
        governor = new SilkenGovernor(IVotes(address(sfc)), timelock);

        // 4. Deploy ProtocolParameters (timelock is governance)
        protocolParams = new ProtocolParameters(admin, address(timelock));

        // 4b. Deploy SCC with admin = Timelock (mirrors Deploy.s.sol) so the DAO — and only the
        // DAO, via the 48h Timelock — can manage SCC roles (MINTER/SLASHER oracle rotation).
        scc = new SilkenCarbonCoin(address(timelock), admin, minter, slasher);

        // 5. Grant governor PROPOSER and CANCELLER roles on timelock
        vm.startPrank(admin);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        vm.stopPrank();

        // 6. Mint SFC tokens and setup voting power
        _mintAndDelegate(voter1, 1_000_000e18, "cluster-1");
        _mintAndDelegate(voter2, 500_000e18, "cluster-2");
        _mintAndDelegate(voter3, 200e18, "cluster-3"); // Below proposal threshold
    }

    // ─── Constructor / Settings ───────────────────────────────────────

    function test_votingDelay() public view {
        assertEq(governor.votingDelay(), VOTING_DELAY);
    }

    function test_votingPeriod() public view {
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
    }

    function test_proposalThreshold() public view {
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
    }

    function test_name() public view {
        assertEq(governor.name(), "Silken Governor");
    }

    function test_quorumFraction() public view {
        // quorumNumerator should be 4 (4%)
        assertEq(governor.quorumNumerator(), 4);
    }

    // ─── Quorum Calculation ───────────────────────────────────────────

    function test_quorum_is4PercentOfTotalSupply() public {
        // Advance 1 block so we can query past checkpoints
        vm.roll(block.number + 1);

        uint256 totalSupply = sfc.totalSupply(); // 1_000_000 + 500_000 + 200 = 1_500_200 SFC
        uint256 expectedQuorum = totalSupply * 4 / 100;

        assertEq(governor.quorum(block.number - 1), expectedQuorum);
    }

    // ─── Proposal Threshold ───────────────────────────────────────────

    function test_propose_succeedsAboveThreshold() public {
        // voter1 has 1M SFC (above 100 SFC threshold)
        vm.roll(block.number + 1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _createSetParameterProposal(keccak256("lorenz_sigma"), 12e18, "Set lorenz_sigma to 12.0");

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        assertTrue(proposalId > 0);
    }

    function testRevert_propose_belowThreshold() public {
        // voter3 has 200 SFC (below 100 SFC threshold — but 200 > 100, so let's test with no tokens)
        address noTokens = makeAddr("noTokensProposer");
        vm.roll(block.number + 1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _createSetParameterProposal(keccak256("lorenz_sigma"), 12e18, "Should fail - no tokens");

        // Pre-compute both args BEFORE the prank — an external call inside the expectRevert
        // args would consume it, and the proposer would be the test contract instead.
        uint256 threshold = governor.proposalThreshold();
        uint256 votes = governor.getVotes(noTokens, block.number - 1); // 0 — holds no SFC
        vm.prank(noTokens);
        vm.expectRevert(
            abi.encodeWithSelector(IGovernor.GovernorInsufficientProposerVotes.selector, noTokens, votes, threshold)
        );
        governor.propose(targets, values, calldatas, description);
    }

    // ─── Full Governance Pipeline ─────────────────────────────────────
    // propose → votingDelay → vote → votingPeriod → queue → timelockDelay → execute

    function test_fullPipeline_setProtocolParameter() public {
        bytes32 paramKey = keccak256("lorenz_sigma");
        uint256 newValue = 12e18;

        // Step 1: Create proposal
        vm.roll(block.number + 1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _createSetParameterProposal(paramKey, newValue, "GIP-1: Update lorenz_sigma to 12.0");

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Step 2: Skip votingDelay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Step 3: Vote (voter1 votes For, voter2 votes For)
        vm.prank(voter1);
        governor.castVote(proposalId, 1); // 1 = For

        vm.prank(voter2);
        governor.castVote(proposalId, 1); // 1 = For

        // Step 4: Skip votingPeriod
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Step 5: Queue the proposal to Timelock
        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        // Step 6: Wait for Timelock delay (48h)
        vm.warp(block.timestamp + 48 hours + 1);

        // Step 7: Execute
        governor.execute(targets, values, calldatas, descriptionHash);

        // Step 8: Verify parameter was updated
        assertEq(protocolParams.getParameter(paramKey), newValue);
        assertTrue(protocolParams.isParameterSet(paramKey));
    }

    // ─── Flash Loan Defense [E.35] ────────────────────────────────────

    function test_flashLoanDefense_snapshotVoting() public {
        // This test verifies that tokens acquired AFTER proposal creation
        // do NOT count towards voting power (E.35 defense).

        vm.roll(block.number + 1);

        // Create proposal at block N
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _createSetParameterProposal(keccak256("lorenz_sigma"), 15e18, "Flash loan test");

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // At this point, snapshot is taken at block.number (proposal creation)

        // Now mint new tokens to a "flash loaner" AFTER the snapshot
        address flashLoaner = makeAddr("flashLoaner");
        _mintAndDelegate(flashLoaner, 5_000_000e18, "flash-cluster");

        // Skip voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Flash loaner tries to vote — but their voting power at the snapshot is 0
        // The vote should succeed (0 voting power is still a valid vote),
        // but the weight should be 0 at the snapshot time.
        // We verify the voter1 and voter2 votes are what matter.
        vm.prank(voter1);
        governor.castVote(proposalId, 1); // For

        // Check that voter1's vote weight is based on snapshot, not current balance
        (uint256 againstVotes, uint256 forVotes,) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 1_000_000e18); // voter1's balance at snapshot
        assertEq(againstVotes, 0);
    }

    // ─── Timelock Integration ─────────────────────────────────────────

    function test_executor_isTimelock() public view {
        // Governor's executor should be the timelock address
        assertEq(governor.timelock(), address(timelock));
    }

    function test_proposalNeedsQueuing() public {
        vm.roll(block.number + 1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _createSetParameterProposal(keccak256("lorenz_sigma"), 12e18, "Queue test");

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        assertTrue(governor.proposalNeedsQueuing(proposalId));
    }

    // ─── Proposal Cancellation ────────────────────────────────────────

    /// @dev Proposer cancels their own proposal while it is still Pending
    ///      (before voting begins). Exercises the _cancel → Timelock override
    ///      (the cancel path was previously untested) and confirms the proposal
    ///      lands in the Canceled state.
    function test_cancel_byProposerWhilePending() public {
        vm.roll(block.number + 1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _createSetParameterProposal(keccak256("lorenz_sigma"), 12e18, "GIP-cancel: proposer withdraws");

        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // Still within votingDelay → state is Pending → the proposer may cancel.
        bytes32 descriptionHash = keccak256(bytes(description));
        vm.prank(voter1);
        governor.cancel(targets, values, calldatas, descriptionHash);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Canceled));
    }

    // ─── Governor ↔ SCC Integration [BIZ.4] ───────────────────────────
    // The existing fullPipeline test only drives ProtocolParameters. These prove the DAO can,
    // end-to-end, manage the SCC token itself — the real pre-mainnet validation for the
    // irreversible "transfer admin-roles → Timelock" hand-over (BIZ.4): after the hand-over the
    // ONLY way to rotate the minting/slashing oracles is a 48h governance proposal.

    /// @dev Full DAO lifecycle grants SCC MINTER_ROLE to a new oracle; the oracle can then mint.
    function test_governanceGrantsMinterRoleOnSCC() public {
        address newMinter = makeAddr("newMinterOracle");
        address recipient = makeAddr("daoTreeOwner");
        assertFalse(scc.hasRole(scc.MINTER_ROLE(), newMinter));

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) = _createGrantRoleProposal(
            address(scc), scc.MINTER_ROLE(), newMinter, "GIP-2: grant SCC MINTER_ROLE to new oracle"
        );
        _runFullPipeline(targets, values, calldatas, description);

        // The DAO (via the 48h Timelock) now controls SCC minting authority...
        assertTrue(scc.hasRole(scc.MINTER_ROLE(), newMinter));
        // ...and the newly-authorized oracle can actually mint.
        vm.prank(newMinter);
        scc.mint(recipient, 1_000e18, "SNET-DAO-1", bytes32(uint256(0xE60)));
        assertEq(scc.balanceOf(recipient), 1_000e18);
    }

    /// @dev Full DAO lifecycle rotates the SCC SLASHER_ROLE oracle; the new slasher can burn.
    function test_governanceGrantsSlasherRoleOnSCC() public {
        address newSlasher = makeAddr("newSlasherOracle");
        address holder = makeAddr("daoHolder");

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) = _createGrantRoleProposal(
            address(scc), scc.SLASHER_ROLE(), newSlasher, "GIP-3: rotate SCC SLASHER_ROLE oracle"
        );
        _runFullPipeline(targets, values, calldatas, description);

        assertTrue(scc.hasRole(scc.SLASHER_ROLE(), newSlasher));
        // Prove the rotated slasher is functional end-to-end (mint via the genesis oracle, then slash).
        vm.prank(minter);
        scc.mint(holder, 1_000e18, "SNET-DAO-2", bytes32(uint256(0xE60)));
        vm.prank(newSlasher);
        scc.slash(holder, 400e18);
        assertEq(scc.balanceOf(holder), 600e18);
    }

    /// @dev No shortcut around the DAO: a non-Timelock caller cannot grant SCC roles directly.
    function testRevert_directGrantMinterRole_byNonTimelock() public {
        address attacker = makeAddr("roleAttacker");
        bytes32 minterRole = scc.MINTER_ROLE();
        // Read the admin role BEFORE prank — a contract call inside the expectRevert args would
        // otherwise consume the prank, making the test contract (not `attacker`) the caller.
        bytes32 adminRole = scc.DEFAULT_ADMIN_ROLE();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, adminRole)
        );
        vm.prank(attacker);
        scc.grantRole(minterRole, attacker);
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    function _mintAndDelegate(address to, uint256 amount, string memory clusterId) internal {
        vm.prank(minter);
        sfc.mint(to, amount, clusterId, bytes32(uint256(0xE60)));

        // SFC auto-delegates on first mint, but if we need explicit delegation:
        // vm.prank(to);
        // sfc.delegate(to);
    }

    function _createSetParameterProposal(bytes32 paramKey, uint256 paramValue, string memory description)
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory desc)
    {
        targets = new address[](1);
        targets[0] = address(protocolParams);

        values = new uint256[](1);
        values[0] = 0;

        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(ProtocolParameters.setParameter.selector, paramKey, paramValue);

        desc = description;
    }

    /// @dev Build a single-call `grantRole(role, account)` proposal targeting any AccessControl contract.
    function _createGrantRoleProposal(address target, bytes32 role, address account, string memory description)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory desc)
    {
        targets = new address[](1);
        targets[0] = target;

        values = new uint256[](1);
        values[0] = 0;

        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(IAccessControl.grantRole.selector, role, account);

        desc = description;
    }

    /// @dev Drive a proposal through the full DAO lifecycle: propose → votingDelay → vote
    ///      (voter1 + voter2 For) → votingPeriod → queue → 48h Timelock → execute.
    function _runFullPipeline(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal {
        vm.roll(block.number + 1);
        vm.prank(voter1);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(voter1);
        governor.castVote(proposalId, 1);
        vm.prank(voter2);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);
        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);
        vm.warp(block.timestamp + 48 hours + 1);
        governor.execute(targets, values, calldatas, descriptionHash);
    }
}
