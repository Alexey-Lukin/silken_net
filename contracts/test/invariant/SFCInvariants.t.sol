// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "forge-std/Test.sol";
import "../../SilkenForestCoin.sol";

/**
 * @title SFCHandler
 * @notice Stateful invariant handler for the SFC governance token. Drives bounded, valid
 *         mint/slash/transfer under the correct roles. All actors self-delegate up front so
 *         that voting power tracks balances for every holder (mint also auto-delegates, but
 *         pre-delegation also covers actors that only ever *receive* transfers).
 */
contract SFCHandler is Test {
    SilkenForestCoin public sfc;
    address public minter;
    address public slasher;
    address[] public actors;

    uint256 public ghostMinted;
    uint256 public ghostSlashed;

    constructor(SilkenForestCoin _sfc, address _minter, address _slasher) {
        sfc = _sfc;
        minter = _minter;
        slasher = _slasher;
        actors.push(makeAddr("sfc_actor_0"));
        actors.push(makeAddr("sfc_actor_1"));
        actors.push(makeAddr("sfc_actor_2"));
        actors.push(makeAddr("sfc_actor_3"));
        for (uint256 i = 0; i < actors.length; i++) {
            vm.prank(actors[i]);
            sfc.delegate(actors[i]);
        }
    }

    function numActors() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function mint(uint256 actorSeed, uint256 amount) external {
        uint256 remaining = sfc.MAX_SUPPLY() - sfc.totalSupply();
        if (remaining == 0) return;
        address to = _actor(actorSeed);
        amount = bound(amount, 1, remaining);
        vm.prank(minter);
        sfc.mint(to, amount, "SNET-CLUSTER-INV", bytes32(uint256(0xE60)));
        ghostMinted += amount;
    }

    function slash(uint256 actorSeed, uint256 amount) external {
        address from = _actor(actorSeed);
        uint256 bal = sfc.balanceOf(from);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        vm.prank(slasher);
        sfc.slash(from, amount);
        ghostSlashed += amount;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = sfc.balanceOf(from);
        if (bal == 0) return;
        amount = bound(amount, 0, bal);
        vm.prank(from);
        sfc.transfer(to, amount);
    }
}

/**
 * @title SFCInvariants
 * @notice Property-based invariants for Silken Forest Coin (ERC20Votes governance token):
 *         1. totalSupply ≤ MAX_SUPPLY (cap);
 *         2. solvency — Σ balances == totalSupply;
 *         3. supply accounting — totalSupply == minted − slashed;
 *         4. governance — Σ voting power == totalSupply (no phantom or lost votes).
 * @dev All actors self-delegate, so getVotes(actor) tracks balanceOf(actor) exactly;
 *      slash() must reduce voting power in lockstep with the burn.
 */
contract SFCInvariants is Test {
    SilkenForestCoin internal sfc;
    SFCHandler internal handler;

    address internal admin = makeAddr("sfc_inv_admin");
    address internal minter = makeAddr("sfc_inv_minter");
    address internal slasher = makeAddr("sfc_inv_slasher");

    function setUp() public {
        sfc = new SilkenForestCoin(admin, admin, minter, slasher); // [SEC.1] pauser=admin (no pause in invariants)
        handler = new SFCHandler(sfc, minter, slasher);
        targetContract(address(handler));
    }

    /// @dev INV-1: hard cap is never breached.
    function invariant_totalSupplyWithinCap() public view {
        assertLe(sfc.totalSupply(), sfc.MAX_SUPPLY());
    }

    /// @dev INV-2: solvency — Σ balances == totalSupply.
    function invariant_solvency() public view {
        uint256 sum;
        uint256 n = handler.numActors();
        for (uint256 i = 0; i < n; i++) {
            sum += sfc.balanceOf(handler.actors(i));
        }
        assertEq(sum, sfc.totalSupply());
    }

    /// @dev INV-3: totalSupply is exactly minted minus slashed (burned).
    function invariant_supplyAccounting() public view {
        assertEq(sfc.totalSupply(), handler.ghostMinted() - handler.ghostSlashed());
    }

    /// @dev INV-4 (governance): Σ voting power == totalSupply — slashing must remove votes
    ///      in lockstep with the burn, else a slashed actor keeps phantom DAO power.
    function invariant_votingPowerMatchesSupply() public view {
        uint256 votes;
        uint256 n = handler.numActors();
        for (uint256 i = 0; i < n; i++) {
            votes += sfc.getVotes(handler.actors(i));
        }
        assertEq(votes, sfc.totalSupply());
    }
}
