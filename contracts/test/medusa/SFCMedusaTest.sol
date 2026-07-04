// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "../../SilkenForestCoin.sol";

/**
 * @title SFCMedusaTest
 * @notice Medusa property-fuzzing harness for the SFC governance token. Mirrors SCCMedusaTest
 *         plus the ERC20Votes property that voting power equals totalSupply. All actors
 *         self-delegate up front (constructor) so getVotes() tracks balanceOf() even for actors
 *         that only ever *receive* transfers — matching test/invariant/SFCInvariants.t.sol.
 *         Canon: docs/05_03 §Smart Contract Audit Roadmap (tool: crytic/medusa).
 */
interface IMedusaVm {
    function prank(address) external;
}

contract SFCMedusaTest {
    IMedusaVm internal constant vm = IMedusaVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    SilkenForestCoin internal sfc;

    address internal constant ADMIN = address(0x1001);
    address internal constant MINTER = address(0x1002);
    address internal constant SLASHER = address(0x1003);
    address[4] internal actors;

    uint256 public ghostMinted;
    uint256 public ghostSlashed;

    constructor() {
        sfc = new SilkenForestCoin(ADMIN, ADMIN, MINTER, SLASHER);
        actors[0] = address(0x2001);
        actors[1] = address(0x2002);
        actors[2] = address(0x2003);
        actors[3] = address(0x2004);
        // Pre-delegate so voting power tracks balance for receive-only actors too.
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(actors[i]);
            sfc.delegate(actors[i]);
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % 4];
    }

    function mint(uint256 actorSeed, uint256 amount) external {
        uint256 remaining = sfc.MAX_SUPPLY() - sfc.totalSupply();
        if (remaining == 0) return;
        amount = (amount % remaining) + 1;
        vm.prank(MINTER);
        sfc.mint(_actor(actorSeed), amount, "MEDUSA-CLUSTER");
        ghostMinted += amount;
    }

    function slash(uint256 actorSeed, uint256 amount) external {
        address from = _actor(actorSeed);
        uint256 bal = sfc.balanceOf(from);
        if (bal == 0) return;
        amount = (amount % bal) + 1;
        vm.prank(SLASHER);
        sfc.slash(from, amount);
        ghostSlashed += amount;
    }

    /// @dev [SLASH.2] maxAmount may EXCEED the balance (up to 2×) — the clamp is the point.
    ///      Ghost accounting uses the RETURNED actual, so property_supplyAccounting +
    ///      property_votingPowerMatchesSupply prove the clamped burn stays consistent.
    function slashUpTo(uint256 actorSeed, uint256 maxAmount) external {
        address from = _actor(actorSeed);
        uint256 bal = sfc.balanceOf(from);
        if (bal == 0) return;
        maxAmount = (maxAmount % (bal * 2)) + 1; // [1, 2×bal] → exercises both branches
        vm.prank(SLASHER);
        uint256 slashed = sfc.slashUpTo(from, maxAmount);
        ghostSlashed += slashed;
    }

    function transferTokens(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        uint256 bal = sfc.balanceOf(from);
        if (bal == 0) return;
        amount = amount % (bal + 1);
        vm.prank(from);
        sfc.transfer(_actor(toSeed), amount);
    }

    function property_totalSupplyWithinCap() public view returns (bool) {
        return sfc.totalSupply() <= sfc.MAX_SUPPLY();
    }

    function property_solvency() public view returns (bool) {
        uint256 sum;
        for (uint256 i = 0; i < 4; i++) {
            sum += sfc.balanceOf(actors[i]);
        }
        return sum == sfc.totalSupply();
    }

    function property_supplyAccounting() public view returns (bool) {
        return sfc.totalSupply() == ghostMinted - ghostSlashed;
    }

    /// @notice INV-4 (governance): Σ voting power == totalSupply — slashing removes votes in
    ///         lockstep with the burn (no phantom DAO power survives a slash).
    function property_votingPowerMatchesSupply() public view returns (bool) {
        uint256 votes;
        for (uint256 i = 0; i < 4; i++) {
            votes += sfc.getVotes(actors[i]);
        }
        return votes == sfc.totalSupply();
    }
}
