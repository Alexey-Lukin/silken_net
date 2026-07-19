// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "forge-std/Test.sol";
import "../SilkenForestCoin.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import "./helpers/Eip712SigUtils.sol";

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
contract SilkenForestCoinTest is Eip712SigUtils {
    SilkenForestCoin public sfc;

    address public admin = makeAddr("admin");
    address public pauser = makeAddr("pauser");
    address public minter = makeAddr("minter");
    address public slasher = makeAddr("slasher");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public unauthorized = makeAddr("unauthorized");

    // [permit/delegateBySig] EIP-712 signer — needs the private key (assigned in setUp).
    address public permitOwner;
    uint256 public permitOwnerPk;

    string public constant CLUSTER_ID = "cluster-alpha-1";

    event ForestMinted(
        address indexed investor,
        uint256 amount,
        bytes32 indexed clusterIdHash,
        string clusterId,
        bytes32 indexed archiveRoot
    );
    event GovernanceSlashed(address indexed investor, uint256 amount, bytes32 contextHash);

    function setUp() public {
        sfc = new SilkenForestCoin(admin, pauser, minter, slasher);
        (permitOwner, permitOwnerPk) = makeAddrAndKey("permitOwner");
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
        assertTrue(sfc.hasRole(sfc.PAUSER_ROLE(), pauser));
        assertTrue(sfc.hasRole(sfc.MINTER_ROLE(), minter));
        assertTrue(sfc.hasRole(sfc.SLASHER_ROLE(), slasher));
    }

    function test_constructor_initialSupplyIsZero() public view {
        assertEq(sfc.totalSupply(), 0);
    }

    function testRevert_constructor_zeroAdmin() public {
        vm.expectRevert("SFC: zero admin");
        new SilkenForestCoin(address(0), pauser, minter, slasher);
    }

    function testRevert_constructor_zeroPauser() public {
        vm.expectRevert("SFC: zero pauser");
        new SilkenForestCoin(admin, address(0), minter, slasher);
    }

    function testRevert_constructor_zeroOracle() public {
        vm.expectRevert("SFC: zero oracle");
        new SilkenForestCoin(admin, pauser, address(0), slasher);
    }

    function testRevert_constructor_zeroSlasher() public {
        vm.expectRevert("SFC: zero slasher oracle");
        new SilkenForestCoin(admin, pauser, minter, address(0));
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
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));

        assertEq(sfc.balanceOf(user1), 1000e18);
        assertEq(sfc.totalSupply(), 1000e18);
    }

    function test_mint_emitsForestMinted() public {
        vm.prank(minter);
        vm.expectEmit(true, true, false, true);
        emit ForestMinted(user1, 1000e18, keccak256(bytes(CLUSTER_ID)), CLUSTER_ID, bytes32(uint256(0xE60)));
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));
    }

    function test_mint_autoDelegatesToSelf() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));

        // After mint, user1 should be self-delegated (ERC20Votes auto-delegation)
        assertEq(sfc.delegates(user1), user1);
    }

    function test_mint_votingPowerActiveImmediately() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));

        // Advance 1 block so checkpoint is queryable
        vm.roll(block.number + 1);

        assertEq(sfc.getVotes(user1), 1000e18);
    }

    function test_mint_secondMintDoesNotReDelegate() public {
        vm.startPrank(minter);
        sfc.mint(user1, 500e18, "cluster-1", bytes32(uint256(0xE60)));

        // user1 delegates to user2 manually
        vm.stopPrank();
        vm.prank(user1);
        sfc.delegate(user2);

        // Second mint should NOT override user1's delegation to user2
        vm.prank(minter);
        sfc.mint(user1, 500e18, "cluster-2", bytes32(uint256(0xE60)));

        assertEq(sfc.delegates(user1), user2);
    }

    function testRevert_mint_unauthorizedCaller() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        sfc.mint(user1, 100e18, CLUSTER_ID, bytes32(uint256(0xE60)));
    }

    function testRevert_mint_zeroRecipient() public {
        vm.prank(minter);
        vm.expectRevert("SFC: zero recipient");
        sfc.mint(address(0), 100e18, CLUSTER_ID, bytes32(uint256(0xE60)));
    }

    function testRevert_mint_zeroAmount() public {
        vm.prank(minter);
        vm.expectRevert("SFC: zero amount");
        sfc.mint(user1, 0, CLUSTER_ID, bytes32(uint256(0xE60)));
    }

    function testRevert_mint_emptyClusterId() public {
        vm.prank(minter);
        vm.expectRevert("SFC: empty clusterId");
        sfc.mint(user1, 100e18, "", bytes32(uint256(0xE60)));
    }

    function testRevert_mint_clusterIdTooLong() public {
        bytes memory longId = new bytes(257);
        for (uint256 i = 0; i < 257; i++) {
            longId[i] = "A";
        }

        vm.prank(minter);
        vm.expectRevert("SFC: clusterId too long");
        sfc.mint(user1, 100e18, string(longId), bytes32(uint256(0xE60)));
    }

    function testRevert_mint_exceedsMaxSupply() public {
        uint256 cap = sfc.MAX_SUPPLY();
        vm.prank(minter);
        vm.expectRevert("SFC: cap exceeded");
        sfc.mint(user1, cap + 1, CLUSTER_ID, bytes32(uint256(0xE60)));
    }

    // ═══════════════════════════════════════════════════════════════════
    // BATCH MINT
    // ═══════════════════════════════════════════════════════════════════

    function test_batchMint_mintsToMultipleRecipients() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        string[] memory ids = new string[](2);

        recipients[0] = user1;
        amounts[0] = 500e18;
        ids[0] = "cl-1";
        recipients[1] = user2;
        amounts[1] = 300e18;
        ids[1] = "cl-2";

        vm.prank(minter);
        sfc.batchMint(recipients, amounts, ids, bytes32(uint256(0xE60)));

        assertEq(sfc.balanceOf(user1), 500e18);
        assertEq(sfc.balanceOf(user2), 300e18);
    }

    function test_batchMint_autoDelegatesAllRecipients() public {
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        string[] memory ids = new string[](2);

        recipients[0] = user1;
        amounts[0] = 500e18;
        ids[0] = "cl-1";
        recipients[1] = user2;
        amounts[1] = 300e18;
        ids[1] = "cl-2";

        vm.prank(minter);
        sfc.batchMint(recipients, amounts, ids, bytes32(uint256(0xE60)));

        assertEq(sfc.delegates(user1), user1);
        assertEq(sfc.delegates(user2), user2);
    }

    function testRevert_batchMint_emptyBatch() public {
        vm.prank(minter);
        vm.expectRevert("SFC: empty batch");
        sfc.batchMint(new address[](0), new uint256[](0), new string[](0), bytes32(uint256(0xE60)));
    }

    function testRevert_batchMint_arrayLengthMismatch() public {
        vm.prank(minter);
        vm.expectRevert("SFC: array length mismatch");
        sfc.batchMint(new address[](2), new uint256[](3), new string[](2), bytes32(uint256(0xE60)));
    }

    function testRevert_batchMint_tooLarge() public {
        uint256 size = sfc.MAX_BATCH_SIZE() + 1;
        address[] memory r = new address[](size);
        uint256[] memory a = new uint256[](size);
        string[] memory d = new string[](size);
        for (uint256 i = 0; i < size; i++) {
            r[i] = user1;
            a[i] = 1e18;
            d[i] = "cl";
        }

        vm.prank(minter);
        vm.expectRevert("SFC: batch too large");
        sfc.batchMint(r, a, d, bytes32(uint256(0xE60)));
    }

    // ═══════════════════════════════════════════════════════════════════
    // SLASH
    // ═══════════════════════════════════════════════════════════════════

    function test_slash_burnsTokens() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));

        vm.prank(slasher);
        sfc.slash(user1, 400e18);

        assertEq(sfc.balanceOf(user1), 600e18);
    }

    function test_slash_emitsGovernanceSlashed() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));

        vm.prank(slasher);
        vm.expectEmit(true, false, false, true);
        emit GovernanceSlashed(user1, 400e18, bytes32(0));
        sfc.slash(user1, 400e18);
    }

    function test_slash_reducesVotingPower() public {
        // [E.1] SFC voting power MUST decrease after slashing
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));
        vm.roll(block.number + 1);
        assertEq(sfc.getVotes(user1), 1000e18);

        vm.prank(slasher);
        sfc.slash(user1, 400e18);
        vm.roll(block.number + 1);

        assertEq(sfc.getVotes(user1), 600e18);
    }

    function testRevert_slash_unauthorizedCaller() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));

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
        sfc.mint(user1, 100e18, CLUSTER_ID, bytes32(uint256(0xE60)));

        vm.prank(slasher);
        vm.expectRevert("SFC: insufficient balance");
        sfc.slash(user1, 200e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // SLASH UP TO [SLASH.2]
    // ═══════════════════════════════════════════════════════════════════

    function test_slashUpTo_burnsRequestedWhenBalanceSufficient() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));

        vm.prank(slasher);
        uint256 slashed = sfc.slashUpTo(user1, 400e18, bytes32(0));

        assertEq(slashed, 400e18);
        assertEq(sfc.balanceOf(user1), 600e18);
    }

    /// @notice [SLASH.2] Voting power of a drained-then-slashed violator goes to ZERO —
    ///         a 1-wei evasion transfer no longer lets governance power survive the slash.
    function test_slashUpTo_clampsAndZeroesVotingPower() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));

        vm.prank(user1);
        sfc.transfer(user2, 1); // 1-wei evasion attempt

        vm.prank(slasher);
        uint256 slashed = sfc.slashUpTo(user1, 1000e18, bytes32(0));
        vm.roll(block.number + 1);

        assertEq(slashed, 1000e18 - 1);
        assertEq(sfc.balanceOf(user1), 0);
        assertEq(sfc.getVotes(user1), 0);
    }

    function test_slashUpTo_emitsActualSlashedAmount() public {
        vm.prank(minter);
        sfc.mint(user1, 100e18, CLUSTER_ID, bytes32(uint256(0xE60)));

        vm.prank(slasher);
        vm.expectEmit(true, false, false, true);
        emit GovernanceSlashed(user1, 100e18, bytes32(uint256(42))); // clamped + contextHash attribution
        sfc.slashUpTo(user1, 500e18, bytes32(uint256(42)));
    }

    function testRevert_slashUpTo_unauthorizedCaller() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));

        vm.prank(unauthorized);
        vm.expectRevert();
        sfc.slashUpTo(user1, 100e18, bytes32(0));
    }

    function testRevert_slashUpTo_zeroInvestor() public {
        vm.prank(slasher);
        vm.expectRevert("SFC: zero investor");
        sfc.slashUpTo(address(0), 100e18, bytes32(0));
    }

    function testRevert_slashUpTo_zeroAmount() public {
        vm.prank(slasher);
        vm.expectRevert("SFC: zero amount");
        sfc.slashUpTo(user1, 0, bytes32(0));
    }

    function testRevert_slashUpTo_nothingToSlash() public {
        vm.prank(slasher);
        vm.expectRevert("SFC: nothing to slash");
        sfc.slashUpTo(user1, 100e18, bytes32(0));
    }

    // ═══════════════════════════════════════════════════════════════════
    // PAUSE — [B-07] SLASH MUST BYPASS PAUSE
    // ═══════════════════════════════════════════════════════════════════

    function test_pause_blocksTransfers() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));

        vm.prank(pauser);
        sfc.pause();

        vm.prank(user1);
        vm.expectRevert();
        sfc.transfer(user2, 100e18);
    }

    function test_pause_blocksMinting() public {
        vm.prank(pauser);
        sfc.pause();

        vm.prank(minter);
        vm.expectRevert();
        sfc.mint(user1, 100e18, CLUSTER_ID, bytes32(uint256(0xE60)));
    }

    function test_pause_allowsSlash() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));

        vm.prank(pauser);
        sfc.pause();

        // Slash MUST work during pause — governance security mechanism
        vm.prank(slasher);
        sfc.slash(user1, 500e18);
        assertEq(sfc.balanceOf(user1), 500e18);
    }

    function test_pause_allowsSlashUpTo() public {
        // [B-07][SLASH.2] slashUpTo is the same security mechanism — must bypass pause too
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));

        vm.prank(pauser);
        sfc.pause();

        vm.prank(slasher);
        uint256 slashed = sfc.slashUpTo(user1, 2000e18, bytes32(0)); // clamps to full balance

        assertEq(slashed, 1000e18);
        assertEq(sfc.balanceOf(user1), 0);
    }

    function test_unpause_resumesOperations() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));

        vm.prank(pauser);
        sfc.pause();
        vm.prank(pauser);
        sfc.unpause();

        vm.prank(user1);
        sfc.transfer(user2, 100e18);
        assertEq(sfc.balanceOf(user2), 100e18);
    }

    /// @notice [SEC.1] DEFAULT_ADMIN (the Timelock in prod) must NOT pause — PAUSER_ROLE only.
    function testRevert_pause_adminCannotPause() public {
        vm.prank(admin);
        vm.expectRevert();
        sfc.pause();
    }

    /// @notice [SEC.1] PAUSER (the Safe) must NOT grant roles — grantRole stays DEFAULT_ADMIN (Timelock).
    function testRevert_pauser_cannotGrantRoles() public {
        bytes32 minterRole = sfc.MINTER_ROLE(); // pre-compute (the prank/expectRevert must hit grantRole)
        vm.prank(pauser);
        vm.expectRevert();
        sfc.grantRole(minterRole, unauthorized);
    }

    // ═══════════════════════════════════════════════════════════════════
    // ADMIN PROTECTION
    // ═══════════════════════════════════════════════════════════════════

    function testRevert_cannotRemoveLastAdmin() public {
        bytes32 adminRole = sfc.DEFAULT_ADMIN_ROLE();
        vm.prank(admin);
        vm.expectRevert("SFC: cannot remove last admin");
        sfc.renounceRole(adminRole, admin);
    }

    function test_canRemoveAdminIfMultiple() public {
        bytes32 adminRole = sfc.DEFAULT_ADMIN_ROLE();
        address admin2 = makeAddr("admin2");
        vm.prank(admin);
        sfc.grantRole(adminRole, admin2);

        vm.prank(admin);
        sfc.renounceRole(adminRole, admin);

        assertFalse(sfc.hasRole(adminRole, admin));
        assertTrue(sfc.hasRole(adminRole, admin2));
    }

    // ═══════════════════════════════════════════════════════════════════
    // ERC20Votes DELEGATION
    // ═══════════════════════════════════════════════════════════════════

    function test_delegate_transfersVotingPower() public {
        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));

        vm.prank(user1);
        sfc.delegate(user2);

        vm.roll(block.number + 1);
        assertEq(sfc.getVotes(user2), 1000e18);
        assertEq(sfc.getVotes(user1), 0);
    }

    function test_getPastVotes_snapshotVoting() public {
        // Use fully hardcoded block numbers to avoid any Yul CSE issues with
        // block.number reads under forge coverage --ir-minimum.
        vm.roll(100);

        vm.prank(minter);
        sfc.mint(user1, 1000e18, CLUSTER_ID, bytes32(uint256(0xE60)));

        // Advance past snapshot block so it becomes queryable as a past block.
        vm.roll(101);

        // Mint more after snapshot (at a later block)
        vm.prank(minter);
        sfc.mint(user1, 500e18, "cluster-2", bytes32(uint256(0xE60)));

        // Advance one more block so block 101 is also in the past
        vm.roll(102);

        // Past votes at block 100 should be 1000e18 (not 1500e18)
        assertEq(sfc.getPastVotes(user1, 100), 1000e18);
        assertEq(sfc.getVotes(user1), 1500e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // NONCES (Diamond Inheritance Resolution)
    // ═══════════════════════════════════════════════════════════════════

    function test_nonces_returnsZeroForNewAddress() public view {
        assertEq(sfc.nonces(user1), 0);
    }

    // ═══════════════════════════════════════════════════════════════════
    // ERC-2612 PERMIT (EIP-712 gasless approvals)
    // ═══════════════════════════════════════════════════════════════════

    function test_permit_setsAllowanceAndIncrementsNonce() public {
        uint256 value = 1_000e18;
        uint256 deadline = block.timestamp + 1 hours;
        assertEq(sfc.nonces(permitOwner), 0);

        bytes32 digest = _permitDigest(address(sfc), permitOwner, user1, value, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerPk, digest);

        vm.expectEmit(true, true, false, true, address(sfc));
        emit IERC20.Approval(permitOwner, user1, value);
        sfc.permit(permitOwner, user1, value, deadline, v, r, s);

        assertEq(sfc.allowance(permitOwner, user1), value);
        assertEq(sfc.nonces(permitOwner), 1);
    }

    function testRevert_permit_expiredDeadline() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _permitDigest(address(sfc), permitOwner, user1, 1e18, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerPk, digest);

        vm.warp(deadline + 1);
        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, deadline));
        sfc.permit(permitOwner, user1, 1e18, deadline, v, r, s);
    }

    function testRevert_permit_replayConsumesNonce() public {
        uint256 value = 5e18;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _permitDigest(address(sfc), permitOwner, user1, value, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerPk, digest);

        sfc.permit(permitOwner, user1, value, deadline, v, r, s);
        assertEq(sfc.nonces(permitOwner), 1);

        vm.expectPartialRevert(ERC20Permit.ERC2612InvalidSigner.selector);
        sfc.permit(permitOwner, user1, value, deadline, v, r, s);
    }

    /// @dev SFC is governance-critical; lock the cross-chain replay invariant for its permit too.
    function testRevert_permit_crossChainReplay() public {
        uint256 value = 5e18;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _permitDigest(address(sfc), permitOwner, user1, value, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerPk, digest);

        vm.chainId(999);
        vm.expectPartialRevert(ERC20Permit.ERC2612InvalidSigner.selector);
        sfc.permit(permitOwner, user1, value, deadline, v, r, s);
    }

    function testRevert_permit_wrongSigner() public {
        (, uint256 attackerPk) = makeAddrAndKey("permitAttacker");
        uint256 value = 5e18;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest = _permitDigest(address(sfc), permitOwner, user1, value, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerPk, digest);

        vm.expectPartialRevert(ERC20Permit.ERC2612InvalidSigner.selector);
        sfc.permit(permitOwner, user1, value, deadline, v, r, s);
    }

    // ═══════════════════════════════════════════════════════════════════
    // ERC20Votes delegateBySig (EIP-712 gasless delegation)
    // ═══════════════════════════════════════════════════════════════════

    /// @dev Happy path: a valid delegation signature moves voting power and burns one nonce.
    function test_delegateBySig_delegatesVotingPower() public {
        vm.prank(minter);
        sfc.mint(permitOwner, 1_000e18, CLUSTER_ID, bytes32(uint256(0xE60))); // auto-delegates to self on first mint
        assertEq(sfc.getVotes(permitOwner), 1_000e18);

        uint256 nonce = sfc.nonces(permitOwner);
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = _delegationDigest(address(sfc), user2, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerPk, digest);

        sfc.delegateBySig(user2, nonce, expiry, v, r, s);

        assertEq(sfc.delegates(permitOwner), user2);
        assertEq(sfc.getVotes(user2), 1_000e18);
        assertEq(sfc.getVotes(permitOwner), 0);
        assertEq(sfc.nonces(permitOwner), nonce + 1);
    }

    function testRevert_delegateBySig_expired() public {
        uint256 nonce = sfc.nonces(permitOwner);
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = _delegationDigest(address(sfc), user2, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerPk, digest);

        vm.warp(expiry + 1);
        vm.expectRevert(abi.encodeWithSelector(IVotes.VotesExpiredSignature.selector, expiry));
        sfc.delegateBySig(user2, nonce, expiry, v, r, s);
    }

    function testRevert_delegateBySig_replayConsumesNonce() public {
        uint256 nonce = sfc.nonces(permitOwner);
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = _delegationDigest(address(sfc), user2, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerPk, digest);

        sfc.delegateBySig(user2, nonce, expiry, v, r, s); // consumes the nonce
        // Replay: signer recovers to permitOwner again, but the nonce counter advanced →
        // _useCheckedNonce reverts InvalidAccountNonce(permitOwner, nonce + 1).
        vm.expectPartialRevert(Nonces.InvalidAccountNonce.selector);
        sfc.delegateBySig(user2, nonce, expiry, v, r, s);
    }

    /// @dev delegateBySig has NO "recovered == owner" check (unlike permit), so a cross-chain
    ///      signature does not revert — it recovers a garbage address and delegates from it
    ///      (zero voting power). The invariant under test: the intended signer's delegation is
    ///      untouched, so no real voting power can be moved by a foreign-chain signature.
    function test_delegateBySig_crossChainDoesNotAffectIntendedSigner() public {
        vm.prank(minter);
        sfc.mint(permitOwner, 1_000e18, CLUSTER_ID, bytes32(uint256(0xE60)));
        assertEq(sfc.delegates(permitOwner), permitOwner);

        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = _delegationDigest(address(sfc), user2, 0, expiry); // nonce 0 on this chain
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerPk, digest);

        vm.chainId(999);
        sfc.delegateBySig(user2, 0, expiry, v, r, s); // delegates from a powerless recovered addr

        assertEq(sfc.delegates(permitOwner), permitOwner); // intended signer untouched
        assertEq(sfc.getVotes(permitOwner), 1_000e18);
    }

    /// @dev Diamond override (`nonces()` over ERC20Permit + Nonces): permit and delegateBySig
    ///      share ONE per-account nonce sequence. A permit burns nonce 0, so the next
    ///      delegateBySig must use nonce 1. Exercises SilkenForestCoin.nonces() override.
    function test_nonce_sharedBetweenPermitAndDelegation() public {
        assertEq(sfc.nonces(permitOwner), 0);

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 pDigest = _permitDigest(address(sfc), permitOwner, user1, 1e18, deadline);
        (uint8 pv, bytes32 pr, bytes32 ps) = vm.sign(permitOwnerPk, pDigest);
        sfc.permit(permitOwner, user1, 1e18, deadline, pv, pr, ps); // burns nonce 0
        assertEq(sfc.nonces(permitOwner), 1);

        uint256 expiry = block.timestamp + 1 hours;
        bytes32 dDigest = _delegationDigest(address(sfc), user2, 1, expiry); // must be nonce 1
        (uint8 dv, bytes32 dr, bytes32 ds) = vm.sign(permitOwnerPk, dDigest);
        sfc.delegateBySig(user2, 1, expiry, dv, dr, ds);

        assertEq(sfc.nonces(permitOwner), 2);
        assertEq(sfc.delegates(permitOwner), user2);
    }

    // ═══════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════

    function testFuzz_mint_arbitraryAmount(uint256 amount) public {
        amount = bound(amount, 1, sfc.MAX_SUPPLY());
        vm.prank(minter);
        sfc.mint(user1, amount, CLUSTER_ID, bytes32(uint256(0xE60)));
        assertEq(sfc.balanceOf(user1), amount);
        assertLe(sfc.totalSupply(), sfc.MAX_SUPPLY());
    }

    function testFuzz_slash_partialAmount(uint256 mintAmt, uint256 slashAmt) public {
        mintAmt = bound(mintAmt, 1, sfc.MAX_SUPPLY());
        slashAmt = bound(slashAmt, 1, mintAmt);

        vm.prank(minter);
        sfc.mint(user1, mintAmt, CLUSTER_ID, bytes32(uint256(0xE60)));

        vm.prank(slasher);
        sfc.slash(user1, slashAmt);

        assertEq(sfc.balanceOf(user1), mintAmt - slashAmt);
    }
}
