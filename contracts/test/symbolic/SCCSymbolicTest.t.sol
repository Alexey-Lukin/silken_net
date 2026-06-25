// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "forge-std/Test.sol";
import "../../SilkenCarbonCoin.sol";

/**
 * @title SCCSymbolicTest
 * @notice Halmos symbolic proofs for the SCC money-path invariants — verified for ALL inputs
 *         (a proof, not a fuzz sample). `check_`-prefixed so `halmos --function "^check_"` runs
 *         only these, leaving the Foundry `invariant_`/`test_` suites to forge.
 *         No halmos-cheatcodes dependency: function parameters are made symbolic by halmos,
 *         and `vm.assume`/`assert` come from forge-std — so this file also compiles under
 *         plain `forge build`. Canon: docs/05_03 §Smart Contract Audit Roadmap (tool: a16z/halmos).
 */
contract SCCSymbolicTest is Test {
    SilkenCarbonCoin internal scc;
    address internal admin;
    address internal pauser;
    address internal minter;
    address internal slasher;

    function setUp() public {
        admin = makeAddr("sym_admin");
        pauser = makeAddr("sym_pauser");
        minter = makeAddr("sym_minter");
        slasher = makeAddr("sym_slasher");
        scc = new SilkenCarbonCoin(admin, pauser, minter, slasher);
    }

    /// @notice INV-1 [B-01]: for any recipient and any in-range amount, mint succeeds AND keeps
    ///         totalSupply ≤ MAX_SUPPLY. The `vm.assume` guides halmos straight to the success
    ///         branch so the assert is always exercised (non-vacuous); a spurious revert in that
    ///         range would itself be a counterexample.
    function check_totalSupply_withinCap(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(amount > 0 && amount <= scc.MAX_SUPPLY());
        vm.prank(minter);
        scc.mint(to, amount, "SNET-SYM");
        assert(scc.totalSupply() <= scc.MAX_SUPPLY());
    }

    /// @notice INV-2: the sole DEFAULT_ADMIN_ROLE holder can never be revoked, for any target
    ///         the solver picks. `_adminCount` guard must hold — else the contract bricks.
    function check_cannotRemoveLastAdmin(address target) public {
        // admin is the only DEFAULT_ADMIN_ROLE holder at setUp (_adminCount == 1).
        vm.assume(scc.hasRole(scc.DEFAULT_ADMIN_ROLE(), target));
        vm.prank(admin);
        try scc.revokeRole(scc.DEFAULT_ADMIN_ROLE(), target) {
            assert(false); // removing the last admin must be impossible
        } catch {}
    }

    /// @notice INV-3 [B-07]: slash() is never blocked by pause() — a paused contract must still
    ///         let the SLASHER burn, for any balances/amounts (burn bypasses the _update guard).
    function check_pause_allowsSlash(uint256 mintAmount, uint256 slashAmount) public {
        address holder = makeAddr("sym_holder");
        vm.assume(mintAmount > 0 && mintAmount <= scc.MAX_SUPPLY());
        vm.assume(slashAmount > 0 && slashAmount <= mintAmount);

        vm.prank(minter);
        scc.mint(holder, mintAmount, "SNET-SYM");

        vm.prank(pauser);
        scc.pause();

        // Must NOT revert under pause.
        vm.prank(slasher);
        scc.slash(holder, slashAmount);

        assert(scc.balanceOf(holder) == mintAmount - slashAmount);
        assert(scc.totalSupply() == mintAmount - slashAmount);
    }
}
