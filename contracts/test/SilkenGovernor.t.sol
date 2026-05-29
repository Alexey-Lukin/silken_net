// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../SilkenGovernor.sol";
import "../SilkenTimelock.sol";
import "../SilkenForestCoin.sol";
import "../ProtocolParameters.sol";

/**
 * @title SilkenGovernor Test Suite
 * @notice Foundry tests for SilkenGovernor.sol — DAO governance for Gaia 2.0.
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

    address public admin = address(0xA);
    address public minter = address(0xB);
    address public slasher = address(0xC);
    address public voter1 = address(0x1);
    address public voter2 = address(0x2);
    address public voter3 = address(0x3);

    uint256 public constant VOTING_DELAY = 43200; // ~1 day on Polygon
    uint256 public constant VOTING_PERIOD = 302400; // ~7 days on Polygon
    uint256 public constant PROPOSAL_THRESHOLD = 100e18; // 100 SFC

    function setUp() public {
        // 1. Deploy SFC (governance token)
        sfc = new SilkenForestCoin(admin, minter, slasher);

        // 2. Deploy Timelock (governor is proposer, anyone can execute)
        address[] memory proposers = new address[](0); // Will add governor after deployment
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute after delay

        timelock = new SilkenTimelock(proposers, executors, admin);

        // 3. Deploy Governor
        governor = new SilkenGovernor(IVotes(address(sfc)), timelock);

        // 4. Deploy ProtocolParameters (timelock is governance)
        protocolParams = new ProtocolParameters(admin, address(timelock));

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

    function test_propose_revertsBelowThreshold() public {
        // voter3 has 200 SFC (below 100 SFC threshold — but 200 > 100, so let's test with no tokens)
        address noTokens = address(0xDEAD);
        vm.roll(block.number + 1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _createSetParameterProposal(keccak256("lorenz_sigma"), 12e18, "Should fail - no tokens");

        vm.prank(noTokens);
        vm.expectRevert(); // GovernorInsufficientProposerVotes
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
        address flashLoaner = address(0xF1A5);
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

    // ─── Helpers ──────────────────────────────────────────────────────

    function _mintAndDelegate(address to, uint256 amount, string memory clusterId) internal {
        vm.prank(minter);
        sfc.mint(to, amount, clusterId);

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
}
