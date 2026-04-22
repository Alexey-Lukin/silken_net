// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../SilkenForestCoin.sol";

/**
 * @title SilkenForestCoin (SFC) Test Suite
 * @notice Comprehensive Foundry tests for SFC — the governance token with ERC20Votes.
 *
 * Best practices applied:
 *  1. makeAddr() for deterministic, labeled test addresses
 *  2. vm.expectEmit with indexed topic matching
 *  3. Snapshot-based voting power verification (ERC20Votes checkpoints)
 *  4. Fuzz tests with bound() for safe input ranges
 *  5. Invariant: totalSupply <= MAX_SUPPLY after any operation
 *  6. Edge cases: auto-delegation, voting power after slash, pause bypass
 */
contract SilkenForestCoinTest is Test {
    SilkenForestCoin public sfc;

    address public admin = makeAddr("admin");
    address public minter = makeAddr("minter");
    address public slasher = makeAddr("slasher");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public unauthorized = makeAddr("unauthorized");

    string public constant CLUSTER_ID = "cluster-alpha-1";

    event ForestMinted(address indexed investor, uint256 amount, bytes32 indexed clusterIdHash, string clusterId);
    event GovernanceSlashed(address indexed investor, uint256 amount);

    function setUp() public {
        sfc = new SilkenForestCoin(admin, minter, slasher);
    }

    // ═══════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════

    function test_constructor_setsNameAndSymbol() public view {
        assertEq(sfc.name(), "Silken Forest Coin");
        assertEq(sfc.symbol(), "SFC");
    }

    function test_constructor_grantsRoles() public view {
        assertTrue(sfc.hasRole(sfc.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(sfc.hasRole(sfc.MINTER_ROLE(), minter));
        assertTrue(sfc.hasRole(sfc.SLASHER_ROLE(), slasher));
    }

    function test_constructor_initialSupplyIsZero() public view {
        assertEq(sfc.totalSupply(), 0);
    }

    function testRevert_constructor_zeroAdmin() public {
        vm.expectRevert("SFC: zero admin");
        new SilkenForestCoin(address(0), minter, slasher);
    }

    function testRevert_constructor_zeroOracle() public {
        vm.expectRevert("SFC: zero oracle");
        new SilkenForestCoin(admin, address(0), slasher);
    }

    function testRevert_constructor_zeroSlasher() public {
        vm.expectRevert("SFC: zero slasher oracle");
        new SilkenForestCoin(admin, minter, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════

    function test_maxSupply() public view {
        assertEq(sfc.MAX_SUPPLY(), 100_000_000 * 1e18);
    }

    function test_maxBatchSize() public view {
        assertEq(sfc.MAX_BATCH_SIZE(), 100);
    }

    // ═══════════════════════════════════════════════════════════════════
    // MINT
    // ═══════════════════════════════════════════════════════════════════

    function test_mint_mintsTokens() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID);

        assertEq(sfc.balanceOf(user1), 1000e18);
        assertEq(sfc.totalSupply(), 1000e18);
    }

    function test_mint_emitsForestMinted() public {
        vm.prank(minter);
        vm.expectEmit(true, true, false, true);
        emit ForestMinted(user1, 1000e18, keccak256(bytes(CLUSTER_ID)), CLUSTER_ID);
        sfc.mint(user1, 1000e18, CLUSTER_ID);
    }

    function test_mint_autoDelegatesToSelf() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID);

        // After mint, user1 should be self-delegated (ERC20Votes auto-delegation)
        assertEq(sfc.delegates(user1), user1);
    }

    function test_mint_votingPowerActiveImmediately() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID);

        // Advance 1 block so checkpoint is queryable
        vm.roll(block.number + 1);

        assertEq(sfc.getVotes(user1), 1000e18);
    }

    function test_mint_secondMintDoesNotReDelegate() public {
        vm.startPrank(minter);
        sfc.mint(user1, 500e18, "cluster-1");

        // user1 delegates to user2 manually
        vm.stopPrank();
        vm.prank(user1);
        sfc.delegate(user2);

        // Second mint should NOT override user1's delegation to user2
        vm.prank(minter);
        sfc.mint(user1, 500e18, "cluster-2");

        assertEq(sfc.delegates(user1), user2);
    }

    function testRevert_mint_unauthorizedCaller() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        sfc.mint(user1, 100e18, CLUSTER_ID);
    }

    function testRevert_mint_zeroRecipient() public {
        vm.prank(minter);
        vm.expectRevert("SFC: zero recipient");
        sfc.mint(address(0), 100e18, CLUSTER_ID);
    }

    function testRevert_mint_zeroAmount() public {
        vm.prank(minter);
        vm.expectRevert("SFC: zero amount");
        sfc.mint(user1, 0, CLUSTER_ID);
    }

    function testRevert_mint_emptyClusterId() public {
        vm.prank(minter);
        vm.expectRevert("SFC: empty clusterId");
        sfc.mint(user1, 100e18, "");
    }

    function testRevert_mint_clusterIdTooLong() public {
        bytes memory longId = new bytes(257);
        for (uint i = 0; i < 257; i++) longId[i] = "A";

        vm.prank(minter);
        vm.expectRevert("SFC: clusterId too long");
        sfc.mint(user1, 100e18, string(longId));
    }

    function testRevert_mint_exceedsMaxSupply() public {
        vm.prank(minter);
        vm.expectRevert("SFC: cap exceeded");
        sfc.mint(user1, sfc.MAX_SUPPLY() + 1, CLUSTER_ID);
    }

    // ═══════════════════════════════════════════════════════════════════
    // BATCH MINT
    // ═══════════════════════════════════════════════════════════════════

    function test_batchMint_mintsToMultipleRecipients() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        string[] memory ids = new string[](2);

        recipients[0] = user1; amounts[0] = 500e18; ids[0] = "cl-1";
        recipients[1] = user2; amounts[1] = 300e18; ids[1] = "cl-2";

        vm.prank(minter);
        sfc.batchMint(recipients, amounts, ids);

        assertEq(sfc.balanceOf(user1), 500e18);
        assertEq(sfc.balanceOf(user2), 300e18);
    }

    function test_batchMint_autoDelegatesAllRecipients() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        string[] memory ids = new string[](2);

        recipients[0] = user1; amounts[0] = 500e18; ids[0] = "cl-1";
        recipients[1] = user2; amounts[1] = 300e18; ids[1] = "cl-2";

        vm.prank(minter);
        sfc.batchMint(recipients, amounts, ids);

        assertEq(sfc.delegates(user1), user1);
        assertEq(sfc.delegates(user2), user2);
    }

    function testRevert_batchMint_emptyBatch() public {
        vm.prank(minter);
        vm.expectRevert("SFC: empty batch");
        sfc.batchMint(new address[](0), new uint256[](0), new string[](0));
    }

    function testRevert_batchMint_arrayLengthMismatch() public {
        vm.prank(minter);
        vm.expectRevert("SFC: array length mismatch");
        sfc.batchMint(new address[](2), new uint256[](3), new string[](2));
    }

    function testRevert_batchMint_tooLarge() public {
        uint256 size = sfc.MAX_BATCH_SIZE() + 1;
        address[] memory r = new address[](size);
        uint256[] memory a = new uint256[](size);
        string[] memory d = new string[](size);
        for (uint i = 0; i < size; i++) {
            r[i] = user1; a[i] = 1e18; d[i] = "cl";
        }

        vm.prank(minter);
        vm.expectRevert("SFC: batch too large");
        sfc.batchMint(r, a, d);
    }

    // ═══════════════════════════════════════════════════════════════════
    // SLASH
    // ═══════════════════════════════════════════════════════════════════

    function test_slash_burnsTokens() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID);

        vm.prank(slasher);
        sfc.slash(user1, 400e18);

        assertEq(sfc.balanceOf(user1), 600e18);
    }

    function test_slash_emitsGovernanceSlashed() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID);

        vm.prank(slasher);
        vm.expectEmit(true, false, false, true);
        emit GovernanceSlashed(user1, 400e18);
        sfc.slash(user1, 400e18);
    }

    function test_slash_reducesVotingPower() public {
        // [E.1] SFC voting power MUST decrease after slashing
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID);
        vm.roll(block.number + 1);
        assertEq(sfc.getVotes(user1), 1000e18);

        vm.prank(slasher);
        sfc.slash(user1, 400e18);
        vm.roll(block.number + 1);

        assertEq(sfc.getVotes(user1), 600e18);
    }

    function testRevert_slash_unauthorizedCaller() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID);

        vm.prank(unauthorized);
        vm.expectRevert();
        sfc.slash(user1, 100e18);
    }

    function testRevert_slash_zeroInvestor() public {
        vm.prank(slasher);
        vm.expectRevert("SFC: zero investor");
        sfc.slash(address(0), 100e18);
    }

    function testRevert_slash_zeroAmount() public {
        vm.prank(slasher);
        vm.expectRevert("SFC: zero amount");
        sfc.slash(user1, 0);
    }

    function testRevert_slash_insufficientBalance() public {
        vm.prank(minter);
        sfc.mint(user1, 100e18, CLUSTER_ID);

        vm.prank(slasher);
        vm.expectRevert("SFC: insufficient balance");
        sfc.slash(user1, 200e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // PAUSE — [B-07] SLASH MUST BYPASS PAUSE
    // ═══════════════════════════════════════════════════════════════════

    function test_pause_blocksTransfers() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID);

        vm.prank(admin);
        sfc.pause();

        vm.prank(user1);
        vm.expectRevert();
        sfc.transfer(user2, 100e18);
    }

    function test_pause_blocksMinting() public {
        vm.prank(admin);
        sfc.pause();

        vm.prank(minter);
        vm.expectRevert();
        sfc.mint(user1, 100e18, CLUSTER_ID);
    }

    function test_pause_allowsSlash() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID);

        vm.prank(admin);
        sfc.pause();

        // Slash MUST work during pause — governance security mechanism
        vm.prank(slasher);
        sfc.slash(user1, 500e18);
        assertEq(sfc.balanceOf(user1), 500e18);
    }

    function test_unpause_resumesOperations() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID);

        vm.prank(admin);
        sfc.pause();
        vm.prank(admin);
        sfc.unpause();

        vm.prank(user1);
        sfc.transfer(user2, 100e18);
        assertEq(sfc.balanceOf(user2), 100e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // ADMIN PROTECTION
    // ═══════════════════════════════════════════════════════════════════

    function testRevert_cannotRemoveLastAdmin() public {
        vm.prank(admin);
        vm.expectRevert("SFC: cannot remove last admin");
        sfc.renounceRole(sfc.DEFAULT_ADMIN_ROLE(), admin);
    }

    function test_canRemoveAdminIfMultiple() public {
        address admin2 = makeAddr("admin2");
        vm.prank(admin);
        sfc.grantRole(sfc.DEFAULT_ADMIN_ROLE(), admin2);

        vm.prank(admin);
        sfc.renounceRole(sfc.DEFAULT_ADMIN_ROLE(), admin);

        assertFalse(sfc.hasRole(sfc.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(sfc.hasRole(sfc.DEFAULT_ADMIN_ROLE(), admin2));
    }

    // ═══════════════════════════════════════════════════════════════════
    // ERC20Votes DELEGATION
    // ═══════════════════════════════════════════════════════════════════

    function test_delegate_transfersVotingPower() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID);

        vm.prank(user1);
        sfc.delegate(user2);

        vm.roll(block.number + 1);
        assertEq(sfc.getVotes(user2), 1000e18);
        assertEq(sfc.getVotes(user1), 0);
    }

    function test_getPastVotes_snapshotVoting() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID);

        vm.roll(block.number + 1);
        uint256 snapshotBlock = block.number;

        // Mint more after snapshot
        vm.prank(minter);
        sfc.mint(user1, 500e18, "cluster-2");
        vm.roll(block.number + 1);

        // Past votes at snapshot should be 1000e18 (not 1500e18)
        assertEq(sfc.getPastVotes(user1, snapshotBlock), 1000e18);
        assertEq(sfc.getVotes(user1), 1500e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // NONCES (Diamond Inheritance Resolution)
    // ═══════════════════════════════════════════════════════════════════

    function test_nonces_returnsZeroForNewAddress() public view {
        assertEq(sfc.nonces(user1), 0);
    }

    // ═══════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════

    function testFuzz_mint_arbitraryAmount(uint256 amount) public {
        amount = bound(amount, 1, sfc.MAX_SUPPLY());
        vm.prank(minter);
        sfc.mint(user1, amount, CLUSTER_ID);
        assertEq(sfc.balanceOf(user1), amount);
        assertLe(sfc.totalSupply(), sfc.MAX_SUPPLY());
    }

    function testFuzz_slash_partialAmount(uint256 mintAmt, uint256 slashAmt) public {
        mintAmt = bound(mintAmt, 1, sfc.MAX_SUPPLY());
        slashAmt = bound(slashAmt, 1, mintAmt);

        vm.prank(minter);
        sfc.mint(user1, mintAmt, CLUSTER_ID);

        vm.prank(slasher);
        sfc.slash(user1, slashAmt);

        assertEq(sfc.balanceOf(user1), mintAmt - slashAmt);
    }
}
