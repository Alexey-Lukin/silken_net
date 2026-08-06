// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "forge-std/Test.sol";
import "../../SilkenCarbonCoin.sol";

/**
 * @title SCCHandler
 * @notice Stateful invariant handler — drives bounded, always-valid mint/slash/transfer
 *         under the correct roles and tracks ghost accounting. `targetContract` points the
 *         fuzzer here (not at SCC directly) so role-gated calls succeed instead of reverting.
 */
contract SCCHandler is Test {
    SilkenCarbonCoin public scc;
    address public minter;
    address public slasher;
    address[] public actors;

    uint256 public ghostMinted;
    uint256 public ghostSlashed;

    constructor(SilkenCarbonCoin _scc, address _minter, address _slasher) {
        scc = _scc;
        minter = _minter;
        slasher = _slasher;
        actors.push(makeAddr("inv_actor_0"));
        actors.push(makeAddr("inv_actor_1"));
        actors.push(makeAddr("inv_actor_2"));
        actors.push(makeAddr("inv_actor_3"));
    }

    function numActors() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Mint a bounded amount that never exceeds the remaining cap (so the call succeeds).
    function mint(uint256 actorSeed, uint256 amount) external {
        uint256 remaining = scc.MAX_SUPPLY() - scc.totalSupply();
        if (remaining == 0) return;
        address to = _actor(actorSeed);
        amount = bound(amount, 1, remaining);
        vm.prank(minter);
        scc.mint(to, amount, "SNET-INVARIANT", bytes32(uint256(0xE60)));
        ghostMinted += amount;
    }

    /// @dev Slash (burn) up to an actor's balance.
    function slash(uint256 actorSeed, uint256 amount) external {
        address from = _actor(actorSeed);
        uint256 bal = scc.balanceOf(from);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        vm.prank(slasher);
        scc.slash(from, amount);
        ghostSlashed += amount;
    }

    /// @dev Move tokens between actors (totalSupply-neutral).
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = scc.balanceOf(from);
        if (bal == 0) return;
        amount = bound(amount, 0, bal);
        vm.prank(from);
        scc.transfer(to, amount);
    }
}

/**
 * @title SCCInvariants
 * @notice Property-based invariants for Silken Carbon Coin:
 *         1. totalSupply never exceeds the hard cap;
 *         2. solvency — Σ holder balances == totalSupply (no leakage/creation);
 *         3. supply accounting — totalSupply == minted − slashed.
 * @dev All tokens are only ever held by the handler's 4 actors (mint→actor, transfer
 *      actor→actor, slash burns), so summing their balances covers every holder.
 */
contract SCCInvariants is Test {
    SilkenCarbonCoin internal scc;
    SCCHandler internal handler;

    address internal admin = makeAddr("inv_admin");
    address internal minter = makeAddr("inv_minter");
    address internal slasher = makeAddr("inv_slasher");

    function setUp() public {
        scc = new SilkenCarbonCoin(admin, admin, minter, slasher); // [SEC.1] pauser=admin (no pause in invariants)
        handler = new SCCHandler(scc, minter, slasher);
        targetContract(address(handler));
    }

    /// @dev INV-1: hard cap is never breached.
    function invariant_totalSupplyWithinCap() public view {
        assertLe(scc.totalSupply(), scc.MAX_SUPPLY());
    }

    /// @dev INV-2: solvency — Σ balances == totalSupply.
    function invariant_solvency() public view {
        uint256 sum;
        uint256 n = handler.numActors();
        for (uint256 i = 0; i < n; i++) {
            sum += scc.balanceOf(handler.actors(i));
        }
        assertEq(sum, scc.totalSupply());
    }

    /// @dev INV-3: totalSupply is exactly minted minus slashed (burned).
    function invariant_supplyAccounting() public view {
        assertEq(scc.totalSupply(), handler.ghostMinted() - handler.ghostSlashed());
    }
}
