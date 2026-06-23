// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "forge-std/Test.sol";
import "../SilkenCarbonCoin.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./helpers/Eip712SigUtils.sol";

/**
 * @title SilkenCarbonCoin (SCC) Test Suite
 * @notice Comprehensive Foundry tests for SCC — the carbon utility token.
 *
 * Best practices applied:
 *  1. Descriptive test names with test_/testFuzz_/testRevert_ prefixes
 *  2. Arrange-Act-Assert pattern
 *  3. vm.prank for caller isolation per test
 *  4. vm.expectRevert with exact error strings
 *  5. vm.expectEmit for event verification
 *  6. Fuzz tests for boundary/arbitrary inputs
 *  7. Constants mirrored from contract for clarity
 *  8. setUp() with minimal deployment — no shared mutable state
 *  9. Gas snapshots via forge test --gas-report
 * 10. Edge case coverage: zero address, zero amount, MAX_SUPPLY boundary
 */
contract SilkenCarbonCoinTest is Eip712SigUtils {
    SilkenCarbonCoin public scc;

    address public admin = makeAddr("admin");
    address public pauser = makeAddr("pauser");
    address public minter = makeAddr("minter");
    address public slasher = makeAddr("slasher");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public unauthorized = makeAddr("unauthorized");

    // [permit] EIP-2612 signer — needs the private key, so assigned in setUp (makeAddrAndKey).
    address public permitOwner;
    uint256 public permitOwnerPk;

    string public constant TREE_DID = "SNET-1A2B3C4D";

    event CarbonMinted(address indexed investor, uint256 amount, bytes32 indexed treeDidHash, string treeDid);
    event TokenSlashed(address indexed investor, uint256 amount);

    function setUp() public {
        scc = new SilkenCarbonCoin(admin, pauser, minter, slasher);
        (permitOwner, permitOwnerPk) = makeAddrAndKey("permitOwner");
    }

    // ═══════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════

    function test_constructor_setsNameAndSymbol() public view {
        assertEq(scc.name(), "Silken Carbon Coin");
        assertEq(scc.symbol(), "SCC");
    }

    function test_constructor_grantsRoles() public view {
        assertTrue(scc.hasRole(scc.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(scc.hasRole(scc.PAUSER_ROLE(), pauser));
        assertTrue(scc.hasRole(scc.MINTER_ROLE(), minter));
        assertTrue(scc.hasRole(scc.SLASHER_ROLE(), slasher));
    }

    function test_constructor_initialSupplyIsZero() public view {
        assertEq(scc.totalSupply(), 0);
    }

    function testRevert_constructor_zeroAdmin() public {
        vm.expectRevert("SCC: zero admin");
        new SilkenCarbonCoin(address(0), pauser, minter, slasher);
    }

    function testRevert_constructor_zeroPauser() public {
        vm.expectRevert("SCC: zero pauser");
        new SilkenCarbonCoin(admin, address(0), minter, slasher);
    }

    function testRevert_constructor_zeroMinter() public {
        vm.expectRevert("SCC: zero minter oracle");
        new SilkenCarbonCoin(admin, pauser, address(0), slasher);
    }

    function testRevert_constructor_zeroSlasher() public {
        vm.expectRevert("SCC: zero slasher oracle");
        new SilkenCarbonCoin(admin, pauser, minter, address(0));
    }

    // ═══════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════

    function test_maxSupply() public view {
        assertEq(scc.MAX_SUPPLY(), 1_000_000_000 * 1e18);
    }

    function test_maxBatchSize() public view {
        assertEq(scc.MAX_BATCH_SIZE(), 100);
    }

    function test_roleConstants() public view {
        assertEq(scc.MINTER_ROLE(), keccak256("MINTER_ROLE"));
        assertEq(scc.SLASHER_ROLE(), keccak256("SLASHER_ROLE"));
        assertEq(scc.PAUSER_ROLE(), keccak256("PAUSER_ROLE"));
    }

    // ═══════════════════════════════════════════════════════════════════
    // MINT
    // ═══════════════════════════════════════════════════════════════════

    function test_mint_mintsTokens() public {
        vm.prank(minter);
        scc.mint(user1, 100e18, TREE_DID);

        assertEq(scc.balanceOf(user1), 100e18);
        assertEq(scc.totalSupply(), 100e18);
    }

    function test_mint_emitsCarbonMinted() public {
        vm.prank(minter);

        vm.expectEmit(true, true, false, true);
        emit CarbonMinted(user1, 100e18, keccak256(bytes(TREE_DID)), TREE_DID);

        scc.mint(user1, 100e18, TREE_DID);
    }

    function test_mintForTree_isSameAsMint() public {
        vm.prank(minter);
        scc.mintForTree(user1, 100e18, TREE_DID);
        assertEq(scc.balanceOf(user1), 100e18);
    }

    function testRevert_mint_unauthorizedCaller() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        scc.mint(user1, 100e18, TREE_DID);
    }

    function testRevert_mint_zeroRecipient() public {
        vm.prank(minter);
        vm.expectRevert("SCC: zero recipient");
        scc.mint(address(0), 100e18, TREE_DID);
    }

    function testRevert_mint_zeroAmount() public {
        vm.prank(minter);
        vm.expectRevert("SCC: zero amount");
        scc.mint(user1, 0, TREE_DID);
    }

    function testRevert_mint_emptyTreeDid() public {
        vm.prank(minter);
        vm.expectRevert("SCC: empty treeDid");
        scc.mint(user1, 100e18, "");
    }

    function testRevert_mint_treeDidTooLong() public {
        // 257 bytes — exceeds 256 limit
        bytes memory longDid = new bytes(257);
        for (uint256 i = 0; i < 257; i++) {
            longDid[i] = "A";
        }

        vm.prank(minter);
        vm.expectRevert("SCC: treeDid too long");
        scc.mint(user1, 100e18, string(longDid));
    }

    function testRevert_mint_exceedsMaxSupply() public {
        uint256 cap = scc.MAX_SUPPLY();
        vm.prank(minter);
        vm.expectRevert("SCC: cap exceeded");
        scc.mint(user1, cap + 1, TREE_DID);
    }

    function test_mint_exactlyMaxSupply() public {
        uint256 cap = scc.MAX_SUPPLY();
        vm.prank(minter);
        scc.mint(user1, cap, TREE_DID);
        assertEq(scc.totalSupply(), cap);
    }

    // ═══════════════════════════════════════════════════════════════════
    // BATCH MINT
    // ═══════════════════════════════════════════════════════════════════

    function test_batchMint_mintsToMultipleRecipients() public {
        address[] memory recipients = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        string[] memory dids = new string[](3);

        recipients[0] = user1;
        amounts[0] = 100e18;
        dids[0] = "SNET-001";
        recipients[1] = user2;
        amounts[1] = 200e18;
        dids[1] = "SNET-002";
        recipients[2] = user1;
        amounts[2] = 50e18;
        dids[2] = "SNET-003";

        vm.prank(minter);
        scc.batchMint(recipients, amounts, dids);

        assertEq(scc.balanceOf(user1), 150e18);
        assertEq(scc.balanceOf(user2), 200e18);
        assertEq(scc.totalSupply(), 350e18);
    }

    function testRevert_batchMint_emptyBatch() public {
        vm.prank(minter);
        vm.expectRevert("SCC: empty batch");
        scc.batchMint(new address[](0), new uint256[](0), new string[](0));
    }

    function testRevert_batchMint_arrayLengthMismatch() public {
        address[] memory r = new address[](2);
        uint256[] memory a = new uint256[](3);
        string[] memory d = new string[](2);

        vm.prank(minter);
        vm.expectRevert("SCC: array length mismatch");
        scc.batchMint(r, a, d);
    }

    function testRevert_batchMint_batchTooLarge() public {
        uint256 size = scc.MAX_BATCH_SIZE() + 1;
        address[] memory r = new address[](size);
        uint256[] memory a = new uint256[](size);
        string[] memory d = new string[](size);

        for (uint256 i = 0; i < size; i++) {
            r[i] = user1;
            a[i] = 1e18;
            d[i] = "SNET-X";
        }

        vm.prank(minter);
        vm.expectRevert("SCC: batch too large");
        scc.batchMint(r, a, d);
    }

    function testRevert_batchMint_exceedsMaxSupply() public {
        address[] memory r = new address[](2);
        uint256[] memory a = new uint256[](2);
        string[] memory d = new string[](2);

        r[0] = user1;
        a[0] = scc.MAX_SUPPLY();
        d[0] = "SNET-1";
        r[1] = user2;
        a[1] = 1;
        d[1] = "SNET-2";

        vm.prank(minter);
        vm.expectRevert("SCC: cap exceeded");
        scc.batchMint(r, a, d);
    }

    // ═══════════════════════════════════════════════════════════════════
    // SLASH
    // ═══════════════════════════════════════════════════════════════════

    function test_slash_burnsTokens() public {
        // Arrange: mint first
        vm.prank(minter);
        scc.mint(user1, 1000e18, TREE_DID);

        // Act: slash
        vm.prank(slasher);
        scc.slash(user1, 300e18);

        // Assert
        assertEq(scc.balanceOf(user1), 700e18);
        assertEq(scc.totalSupply(), 700e18);
    }

    function test_slash_emitsTokenSlashed() public {
        vm.prank(minter);
        scc.mint(user1, 1000e18, TREE_DID);

        vm.prank(slasher);
        vm.expectEmit(true, false, false, true);
        emit TokenSlashed(user1, 300e18);
        scc.slash(user1, 300e18);
    }

    function testRevert_slash_unauthorizedCaller() public {
        vm.prank(minter);
        scc.mint(user1, 1000e18, TREE_DID);

        vm.prank(unauthorized);
        vm.expectRevert();
        scc.slash(user1, 100e18);
    }

    function testRevert_slash_zeroInvestor() public {
        vm.prank(slasher);
        vm.expectRevert("SCC: zero investor");
        scc.slash(address(0), 100e18);
    }

    function testRevert_slash_zeroAmount() public {
        vm.prank(slasher);
        vm.expectRevert("SCC: zero amount");
        scc.slash(user1, 0);
    }

    function testRevert_slash_insufficientBalance() public {
        vm.prank(minter);
        scc.mint(user1, 100e18, TREE_DID);

        vm.prank(slasher);
        vm.expectRevert("SCC: insufficient balance");
        scc.slash(user1, 200e18);
    }

    // ═══════════════════════════════════════════════════════════════════
    // PAUSE / UNPAUSE
    // ═══════════════════════════════════════════════════════════════════

    function test_pause_blocksTransfers() public {
        vm.prank(minter);
        scc.mint(user1, 1000e18, TREE_DID);

        vm.prank(pauser);
        scc.pause();

        vm.prank(user1);
        vm.expectRevert();
        scc.transfer(user2, 100e18);
    }

    function test_pause_blocksMinting() public {
        vm.prank(pauser);
        scc.pause();

        vm.prank(minter);
        vm.expectRevert();
        scc.mint(user1, 100e18, TREE_DID);
    }

    function test_pause_allowsSlash() public {
        // [B-07] Slash MUST work during pause — security mechanism
        vm.prank(minter);
        scc.mint(user1, 1000e18, TREE_DID);

        vm.prank(pauser);
        scc.pause();

        vm.prank(slasher);
        scc.slash(user1, 500e18); // Should NOT revert

        assertEq(scc.balanceOf(user1), 500e18);
    }

    function test_unpause_allowsTransfersAgain() public {
        vm.prank(minter);
        scc.mint(user1, 1000e18, TREE_DID);

        vm.prank(pauser);
        scc.pause();
        vm.prank(pauser);
        scc.unpause();

        vm.prank(user1);
        scc.transfer(user2, 100e18);
        assertEq(scc.balanceOf(user2), 100e18);
    }

    function testRevert_pause_unauthorizedCaller() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        scc.pause();
    }

    /// @notice [SEC.1] DEFAULT_ADMIN (the Timelock in prod) must NOT be able to pause —
    ///         pause is PAUSER_ROLE only (the Safe). Proves the role split.
    function testRevert_pause_adminCannotPause() public {
        vm.prank(admin);
        vm.expectRevert();
        scc.pause();
    }

    /// @notice [SEC.1] PAUSER (the Safe) must NOT be able to grant roles — the catastrophic
    ///         grantRole(MINTER) power stays with DEFAULT_ADMIN (the Timelock).
    function testRevert_pauser_cannotGrantRoles() public {
        bytes32 minterRole = scc.MINTER_ROLE(); // pre-compute (the prank/expectRevert must hit grantRole)
        vm.prank(pauser);
        vm.expectRevert();
        scc.grantRole(minterRole, unauthorized);
    }

    // ═══════════════════════════════════════════════════════════════════
    // ADMIN PROTECTION
    // ═══════════════════════════════════════════════════════════════════

    function testRevert_cannotRemoveLastAdmin() public {
        bytes32 adminRole = scc.DEFAULT_ADMIN_ROLE();
        vm.prank(admin);
        vm.expectRevert("SCC: cannot remove last admin");
        scc.renounceRole(adminRole, admin);
    }

    function test_canRemoveAdminIfMultiple() public {
        bytes32 adminRole = scc.DEFAULT_ADMIN_ROLE();
        address admin2 = makeAddr("admin2");
        vm.prank(admin);
        scc.grantRole(adminRole, admin2);

        vm.prank(admin);
        scc.renounceRole(adminRole, admin);

        assertFalse(scc.hasRole(adminRole, admin));
        assertTrue(scc.hasRole(adminRole, admin2));
    }

    // ═══════════════════════════════════════════════════════════════════
    // ERC20 PERMIT
    // ═══════════════════════════════════════════════════════════════════

    function test_supportsERC20Permit() public view {
        // Verify DOMAIN_SEPARATOR exists (EIP-712)
        bytes32 ds = scc.DOMAIN_SEPARATOR();
        assertTrue(ds != bytes32(0));
    }

    /// @dev Happy path: a valid signature sets the allowance and burns exactly one nonce.
    function test_permit_setsAllowanceAndIncrementsNonce() public {
        uint256 value = 1_000e18;
        uint256 deadline = block.timestamp + 1 hours;
        assertEq(scc.nonces(permitOwner), 0);

        bytes32 digest = _permitDigest(address(scc), permitOwner, user1, value, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerPk, digest);

        vm.expectEmit(true, true, false, true, address(scc));
        emit IERC20.Approval(permitOwner, user1, value);
        scc.permit(permitOwner, user1, value, deadline, v, r, s);

        assertEq(scc.allowance(permitOwner, user1), value);
        assertEq(scc.nonces(permitOwner), 1);
    }

    /// @dev A signature presented after its deadline is rejected (exact error + arg).
    function testRevert_permit_expiredDeadline() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _permitDigest(address(scc), permitOwner, user1, 1e18, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerPk, digest);

        vm.warp(deadline + 1); // now past the deadline
        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, deadline));
        scc.permit(permitOwner, user1, 1e18, deadline, v, r, s);
    }

    /// @dev Replaying a consumed signature fails: the nonce already advanced, so the
    ///      recovered signer no longer matches the owner. Proves nonce-based replay safety.
    function testRevert_permit_replayConsumesNonce() public {
        uint256 value = 5e18;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _permitDigest(address(scc), permitOwner, user1, value, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerPk, digest);

        scc.permit(permitOwner, user1, value, deadline, v, r, s); // consumes nonce 0
        assertEq(scc.nonces(permitOwner), 1);

        vm.expectPartialRevert(ERC20Permit.ERC2612InvalidSigner.selector);
        scc.permit(permitOwner, user1, value, deadline, v, r, s); // same sig, now nonce 1 → mismatch
    }

    /// @dev Cross-chain replay: a permit signed for THIS chain is rejected on another chain.
    ///      OZ rebuilds the EIP-712 domain separator when `block.chainid` changes, so the
    ///      recovered signer no longer matches the owner. SCC is Polygon-only — this locks the
    ///      invariant against a future regression (e.g. a hardcoded/cached domain separator).
    function testRevert_permit_crossChainReplay() public {
        uint256 value = 5e18;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = _permitDigest(address(scc), permitOwner, user1, value, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerPk, digest);

        vm.chainId(999); // simulate the same contract/key on a different chain
        vm.expectPartialRevert(ERC20Permit.ERC2612InvalidSigner.selector);
        scc.permit(permitOwner, user1, value, deadline, v, r, s);
    }

    /// @dev An owner-bound digest signed by a DIFFERENT key is rejected (forged signature).
    function testRevert_permit_wrongSigner() public {
        (, uint256 attackerPk) = makeAddrAndKey("permitAttacker");
        uint256 value = 5e18;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest = _permitDigest(address(scc), permitOwner, user1, value, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerPk, digest); // wrong key

        vm.expectPartialRevert(ERC20Permit.ERC2612InvalidSigner.selector);
        scc.permit(permitOwner, user1, value, deadline, v, r, s);
    }

    /// @dev Property: any value / future deadline yields a valid allowance + single nonce burn.
    function testFuzz_permit_setsAllowance(uint256 value, uint64 deadlineOffset) public {
        uint256 deadline = block.timestamp + bound(deadlineOffset, 1, 365 days);
        bytes32 digest = _permitDigest(address(scc), permitOwner, user1, value, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(permitOwnerPk, digest);

        scc.permit(permitOwner, user1, value, deadline, v, r, s);

        assertEq(scc.allowance(permitOwner, user1), value);
        assertEq(scc.nonces(permitOwner), 1);
    }

    // ═══════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════

    function testFuzz_mint_arbitraryAmount(uint256 amount) public {
        amount = bound(amount, 1, scc.MAX_SUPPLY());
        vm.prank(minter);
        scc.mint(user1, amount, TREE_DID);
        assertEq(scc.balanceOf(user1), amount);
    }

    function testFuzz_slash_partialAmount(uint256 mintAmt, uint256 slashAmt) public {
        mintAmt = bound(mintAmt, 1, scc.MAX_SUPPLY());
        slashAmt = bound(slashAmt, 1, mintAmt);

        vm.prank(minter);
        scc.mint(user1, mintAmt, TREE_DID);

        vm.prank(slasher);
        scc.slash(user1, slashAmt);

        assertEq(scc.balanceOf(user1), mintAmt - slashAmt);
    }

    function testFuzz_mint_treeDidMaxLength(uint8 len) public {
        len = uint8(bound(uint256(len), 1, 256));
        bytes memory did = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            did[i] = "X";
        }

        vm.prank(minter);
        scc.mint(user1, 1e18, string(did));
        assertEq(scc.balanceOf(user1), 1e18);
    }
}
