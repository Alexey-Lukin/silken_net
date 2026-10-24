// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import "forge-std/Test.sol";
import "../../SilkenCarbonCoin.sol";

/**
 * @title SCCSymbolicTest
 * @notice Symbolic proofs for the SCC money-path invariants — verified for ALL inputs
 *         (a proof, not a fuzz sample). `prove_`-prefixed: run by BOTH engines — hevm
 *         (`hevm test --match "^prove_"`) and halmos (`--function "^(check|prove)_"`) — so each
 *         proof has two independent witnesses; forge never runs a `prove_` function. No
 *         tool-specific cheatcodes: parameters are made symbolic by the engine, and
 *         `vm.assume`/`assert` come from forge-std, so this file also compiles under plain
 *         `forge build`. Canon: docs/05_03 §Smart Contract Audit Roadmap.
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
    ///         totalSupply ≤ MAX_SUPPLY. The `vm.assume` guides the solver straight to the success
    ///         branch so the assert is always exercised (non-vacuous); a spurious revert in that
    ///         range would itself be a counterexample.
    function prove_totalSupply_withinCap(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(amount > 0 && amount <= scc.MAX_SUPPLY());
        vm.prank(minter);
        scc.mint(to, amount, "SNET-SYM", bytes32(uint256(0xE60)));
        assert(scc.totalSupply() <= scc.MAX_SUPPLY());
    }

    /// @notice INV-2: the sole DEFAULT_ADMIN_ROLE holder can never be revoked, for any target
    ///         the solver picks. `_adminCount` guard must hold — else the contract bricks.
    function prove_cannotRemoveLastAdmin(address target) public {
        // admin is the only DEFAULT_ADMIN_ROLE holder at setUp (_adminCount == 1).
        // The role is read BEFORE the prank: an external call in the argument list would
        // otherwise run first and, in hevm, consume the prank — revokeRole then reverts
        // from this contract, the catch swallows it, and the proof passes on ANY contract
        // (mutation-measured 2026-10-24: guard removed → halmos red, hevm green).
        bytes32 role = scc.DEFAULT_ADMIN_ROLE();
        vm.assume(scc.hasRole(role, target));
        vm.prank(admin);
        try scc.revokeRole(role, target) {
            assert(false); // removing the last admin must be impossible
        } catch {}
    }

    /// @notice INV-3 [B-07]: slash() is never blocked by pause() — a paused contract must still
    ///         let the SLASHER burn, for any balances/amounts (burn bypasses the _update guard).
    function prove_pause_allowsSlash(uint256 mintAmount, uint256 slashAmount) public {
        address holder = makeAddr("sym_holder");
        vm.assume(mintAmount > 0 && mintAmount <= scc.MAX_SUPPLY());
        vm.assume(slashAmount > 0 && slashAmount <= mintAmount);

        vm.prank(minter);
        scc.mint(holder, mintAmount, "SNET-SYM", bytes32(uint256(0xE60)));

        vm.prank(pauser);
        scc.pause();

        // Must NOT revert under pause.
        vm.prank(slasher);
        scc.slash(holder, slashAmount);

        assert(scc.balanceOf(holder) == mintAmount - slashAmount);
        assert(scc.totalSupply() == mintAmount - slashAmount);
    }

    /// @notice INV-4 [SLASH.2]: for ANY balance / drain / request, slashUpTo burns exactly
    ///         min(remaining, maxAmount) — an evasion transfer can only shrink the burn to
    ///         what is left, never void the penalty (the strict slash() would revert instead).
    function prove_slashUpTo_clampsToBalance(uint256 mintAmount, uint256 drained, uint256 maxAmount) public {
        address holder = makeAddr("sym_holder");
        address sink = makeAddr("sym_sink");
        vm.assume(mintAmount > 1 && mintAmount <= scc.MAX_SUPPLY());
        vm.assume(drained < mintAmount); // leave a nonzero remainder
        vm.assume(maxAmount > 0);

        vm.prank(minter);
        scc.mint(holder, mintAmount, "SNET-SYM", bytes32(uint256(0xE60)));
        vm.prank(holder);
        scc.transfer(sink, drained); // the evasion attempt

        uint256 remaining = mintAmount - drained;

        vm.prank(slasher);
        uint256 slashed = scc.slashUpTo(holder, maxAmount, bytes32(0));

        assert(slashed == (remaining < maxAmount ? remaining : maxAmount));
        assert(scc.balanceOf(holder) == remaining - slashed);
        assert(scc.totalSupply() == mintAmount - slashed);
    }
}
