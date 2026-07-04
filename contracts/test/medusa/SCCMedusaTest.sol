// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "../../SilkenCarbonCoin.sol";

/**
 * @title SCCMedusaTest
 * @notice Medusa property-fuzzing harness for SCC. Medusa has no `targetContract()` routing,
 *         so the handler (wrapper calls + ghost accounting) and the `property_*` checks live
 *         in ONE contract. Mirrors test/invariant/SCCInvariants.t.sol but with bool-returning
 *         `property_` functions (checked after every call sequence). `vm.prank` is reached via
 *         the HEVM cheatcode address (Medusa supports it); bounds use `%` (no forge-std dep).
 *         Canon: docs/05_03 §Smart Contract Audit Roadmap (tool: crytic/medusa).
 */
interface IMedusaVm {
    function prank(address) external;
}

contract SCCMedusaTest {
    IMedusaVm internal constant vm = IMedusaVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    SilkenCarbonCoin internal scc;

    address internal constant ADMIN = address(0x1001);
    address internal constant MINTER = address(0x1002);
    address internal constant SLASHER = address(0x1003);
    address[4] internal actors;

    uint256 public ghostMinted;
    uint256 public ghostSlashed;

    constructor() {
        scc = new SilkenCarbonCoin(ADMIN, ADMIN, MINTER, SLASHER);
        actors[0] = address(0x2001);
        actors[1] = address(0x2002);
        actors[2] = address(0x2003);
        actors[3] = address(0x2004);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % 4];
    }

    // ── Wrapper calls the fuzzer drives (always-valid, role-correct) ──────────

    function mint(uint256 actorSeed, uint256 amount) external {
        uint256 remaining = scc.MAX_SUPPLY() - scc.totalSupply();
        if (remaining == 0) return;
        amount = (amount % remaining) + 1; // [1, remaining] → never exceeds cap
        vm.prank(MINTER);
        scc.mint(_actor(actorSeed), amount, "MEDUSA-INV");
        ghostMinted += amount;
    }

    function slash(uint256 actorSeed, uint256 amount) external {
        address from = _actor(actorSeed);
        uint256 bal = scc.balanceOf(from);
        if (bal == 0) return;
        amount = (amount % bal) + 1; // [1, bal]
        vm.prank(SLASHER);
        scc.slash(from, amount);
        ghostSlashed += amount;
    }

    /// @dev [SLASH.2] maxAmount may EXCEED the balance (up to 2×) — the clamp is the point.
    ///      Ghost accounting uses the RETURNED actual, so property_supplyAccounting proves
    ///      the emitted/returned amount matches what was really burned.
    function slashUpTo(uint256 actorSeed, uint256 maxAmount) external {
        address from = _actor(actorSeed);
        uint256 bal = scc.balanceOf(from);
        if (bal == 0) return;
        maxAmount = (maxAmount % (bal * 2)) + 1; // [1, 2×bal] → exercises both branches
        vm.prank(SLASHER);
        uint256 slashed = scc.slashUpTo(from, maxAmount);
        ghostSlashed += slashed;
    }

    function transferTokens(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        uint256 bal = scc.balanceOf(from);
        if (bal == 0) return;
        amount = amount % (bal + 1); // [0, bal]
        vm.prank(from);
        scc.transfer(_actor(toSeed), amount);
    }

    // ── Properties (Medusa checks these return true after every call) ─────────

    /// @notice INV-1: hard cap is never breached.
    function property_totalSupplyWithinCap() public view returns (bool) {
        return scc.totalSupply() <= scc.MAX_SUPPLY();
    }

    /// @notice INV-2: solvency — Σ actor balances == totalSupply (tokens only ever live here).
    function property_solvency() public view returns (bool) {
        uint256 sum;
        for (uint256 i = 0; i < 4; i++) {
            sum += scc.balanceOf(actors[i]);
        }
        return sum == scc.totalSupply();
    }

    /// @notice INV-3: totalSupply == minted − slashed.
    function property_supplyAccounting() public view returns (bool) {
        return scc.totalSupply() == ghostMinted - ghostSlashed;
    }
}
