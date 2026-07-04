// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "forge-std/Test.sol";
import "../../SilkenForestCoin.sol";

/**
 * @title SFCSymbolicTest
 * @notice Halmos symbolic proofs for the SFC governance token — mirrors the SCC money-path
 *         invariants plus the ERC20Votes-specific property that voting power tracks balance
 *         through a slash (no phantom DAO power survives a burn). `check_`-prefixed; compiles
 *         under plain `forge build` (no halmos-cheatcodes dep).
 *         Canon: docs/05_03 §Smart Contract Audit Roadmap (tool: a16z/halmos).
 */
contract SFCSymbolicTest is Test {
    SilkenForestCoin internal sfc;
    address internal admin;
    address internal pauser;
    address internal minter;
    address internal slasher;

    function setUp() public {
        admin = makeAddr("sym_admin");
        pauser = makeAddr("sym_pauser");
        minter = makeAddr("sym_minter");
        slasher = makeAddr("sym_slasher");
        sfc = new SilkenForestCoin(admin, pauser, minter, slasher);
    }

    /// @notice INV-1 [B-01]: for any recipient and any in-range amount, mint succeeds AND keeps
    ///         totalSupply ≤ MAX_SUPPLY (assume guides halmos to the success branch — non-vacuous).
    function check_totalSupply_withinCap(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(amount > 0 && amount <= sfc.MAX_SUPPLY());
        vm.prank(minter);
        sfc.mint(to, amount, "SNET-CLUSTER-SYM");
        assert(sfc.totalSupply() <= sfc.MAX_SUPPLY());
    }

    /// @notice INV-2: the sole DEFAULT_ADMIN_ROLE holder can never be revoked.
    function check_cannotRemoveLastAdmin(address target) public {
        vm.assume(sfc.hasRole(sfc.DEFAULT_ADMIN_ROLE(), target));
        vm.prank(admin);
        try sfc.revokeRole(sfc.DEFAULT_ADMIN_ROLE(), target) {
            assert(false);
        } catch {}
    }

    /// @notice INV-3 [B-07]: slash() is never blocked by pause().
    function check_pause_allowsSlash(uint256 mintAmount, uint256 slashAmount) public {
        address holder = makeAddr("sym_holder");
        vm.assume(mintAmount > 0 && mintAmount <= sfc.MAX_SUPPLY());
        vm.assume(slashAmount > 0 && slashAmount <= mintAmount);

        vm.prank(minter);
        sfc.mint(holder, mintAmount, "SNET-CLUSTER-SYM");

        vm.prank(pauser);
        sfc.pause();

        vm.prank(slasher);
        sfc.slash(holder, slashAmount);

        assert(sfc.balanceOf(holder) == mintAmount - slashAmount);
        assert(sfc.totalSupply() == mintAmount - slashAmount);
    }

    /// @notice INV-4 (governance): voting power tracks balance through a slash — a slashed
    ///         holder keeps no phantom DAO votes. mint() auto-delegates to self, so
    ///         getVotes(holder) must equal balanceOf(holder) after the burn, for any amounts.
    function check_votingPowerTracksBalanceAfterSlash(uint256 mintAmount, uint256 slashAmount) public {
        address holder = makeAddr("sym_holder");
        vm.assume(mintAmount > 0 && mintAmount <= sfc.MAX_SUPPLY());
        vm.assume(slashAmount > 0 && slashAmount <= mintAmount);

        vm.prank(minter);
        sfc.mint(holder, mintAmount, "SNET-CLUSTER-SYM"); // auto-delegates holder→holder

        vm.prank(slasher);
        sfc.slash(holder, slashAmount);

        assert(sfc.getVotes(holder) == sfc.balanceOf(holder));
    }

    /// @notice INV-5 [SLASH.2]: slashUpTo burns exactly min(remaining, maxAmount) — an evasion
    ///         transfer can only shrink the burn, never void it — and voting power still tracks
    ///         the post-burn balance (no phantom DAO votes survive the clamped slash).
    function check_slashUpTo_clampsToBalance(uint256 mintAmount, uint256 drained, uint256 maxAmount) public {
        address holder = makeAddr("sym_holder");
        address sink = makeAddr("sym_sink");
        vm.assume(mintAmount > 1 && mintAmount <= sfc.MAX_SUPPLY());
        vm.assume(drained < mintAmount); // leave a nonzero remainder
        vm.assume(maxAmount > 0);

        vm.prank(minter);
        sfc.mint(holder, mintAmount, "SNET-CLUSTER-SYM");
        vm.prank(holder);
        sfc.transfer(sink, drained); // the evasion attempt

        uint256 remaining = mintAmount - drained;

        vm.prank(slasher);
        uint256 slashed = sfc.slashUpTo(holder, maxAmount, bytes32(0));

        assert(slashed == (remaining < maxAmount ? remaining : maxAmount));
        assert(sfc.balanceOf(holder) == remaining - slashed);
        assert(sfc.getVotes(holder) == sfc.balanceOf(holder));
    }
}
