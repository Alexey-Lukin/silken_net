// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "../../SilkenForestCoin.sol";

/**
 * @title SFCMedusaTest
 * @notice Medusa property-fuzzing harness for SFC (governance token). Same shape as
 *         SCCMedusaTest — handler + `property_*` in one contract, HEVM cheatcode prank,
 *         `%` bounds — plus the ERC20Votes axis: voting power must track the burn.
 *         Canon: docs/05_03 §Smart Contract Audit Roadmap (tool: crytic/medusa).
 *
 *         [CONTRACT.2] `batchMint` had ZERO fuzz coverage here, and on SFC that mattered
 *         more than on SCC: batchMint carries the ONE piece of logic that a plain `_mint`
 *         loop does not — the auto-delegate branch (SilkenForestCoin.sol, `if
 *         (delegates(recipients[i]) == address(0)) _delegate(...)`). It is also the branch
 *         a naive harness silently kills: the constructor pre-delegates every actor, so
 *         `delegates(r[i]) == address(0)` would be permanently false and the branch would
 *         never execute once. Hence actors[4..5] below are deliberately NOT pre-delegated
 *         and are reachable ONLY through batchMint — they are the fresh addresses that
 *         make the branch fire. They are kept out of transfer/mint/slash on purpose: a
 *         transfer into an undelegated address would break votes == supply legitimately
 *         (OZ by design), and that is an invariant, not a preference.
 *
 *         Panics are NOT caught (a caught Panic is invisible to Medusa, which inspects only
 *         the top-level call result) and ghost accounting is summed from the INPUT amounts,
 *         never from a totalSupply delta — the two decisions are coupled: atomicity of the
 *         ghost update depends entirely on there being no catch.
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

    uint256 internal constant POOL = 4; // general pool: mint / slash / transfer
    uint256 internal constant ACTORS = 6; // + [4..5] batch-only, deliberately undelegated
    address[ACTORS] internal actors;

    uint256 public ghostMinted;
    uint256 public ghostSlashed;
    mapping(address => uint256) public ghostBalance;

    uint256 internal constant AMOUNT_CAP = 1e21;
    uint256 internal constant MAX_BATCH = 100;

    constructor() {
        sfc = new SilkenForestCoin(ADMIN, ADMIN, MINTER, SLASHER);
        actors[0] = address(0x2001);
        actors[1] = address(0x2002);
        actors[2] = address(0x2003);
        actors[3] = address(0x2004);
        actors[4] = address(0x2005);
        actors[5] = address(0x2006);
        // Pre-delegate ONLY the general pool, so voting power tracks balance for
        // receive-only actors. actors[4..5] stay undelegated ON PURPOSE — see the
        // contract notice: they are what keeps batchMint's auto-delegate branch alive.
        for (uint256 i = 0; i < POOL; i++) {
            vm.prank(actors[i]);
            sfc.delegate(actors[i]);
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % POOL];
    }

    function _batchRecipient(uint256 seed) internal view returns (address) {
        return actors[seed % ACTORS];
    }

    // ── Wrapper calls the fuzzer drives (always-valid, role-correct) ──────────

    function mint(uint256 actorSeed, uint256 amount) external {
        uint256 remaining = sfc.MAX_SUPPLY() - sfc.totalSupply();
        if (remaining == 0) return;
        amount = (amount % remaining) + 1;
        address to = _actor(actorSeed);
        vm.prank(MINTER);
        sfc.mint(to, amount, "MEDUSA-CLUSTER", bytes32(uint256(0xE60)));
        ghostMinted += amount;
        ghostBalance[to] += amount;
    }

    function slash(uint256 actorSeed, uint256 amount) external {
        address from = _actor(actorSeed);
        uint256 bal = sfc.balanceOf(from);
        if (bal == 0) return;
        amount = (amount % bal) + 1;
        vm.prank(SLASHER);
        sfc.slash(from, amount);
        ghostSlashed += amount;
        ghostBalance[from] -= amount;
    }

    /// @dev [SLASH.2] maxAmount may EXCEED the balance (up to 2×) — the clamp is the point.
    function slashUpTo(uint256 actorSeed, uint256 maxAmount) external {
        address from = _actor(actorSeed);
        uint256 bal = sfc.balanceOf(from);
        if (bal == 0) return;
        maxAmount = (maxAmount % (bal * 2)) + 1;
        vm.prank(SLASHER);
        uint256 slashed = sfc.slashUpTo(from, maxAmount, bytes32(0));
        ghostSlashed += slashed;
        ghostBalance[from] -= slashed;
    }

    function transferTokens(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = sfc.balanceOf(from);
        if (bal == 0) return;
        amount = amount % (bal + 1);
        vm.prank(from);
        sfc.transfer(to, amount);
        if (from != to) {
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
        }
    }

    // ── [CONTRACT.2] pause / unpause — B-07 INSIDE a sequence ────────────────

    /// @notice Mirror of the SCC harness (full rationale there), but the SFC side carries a
    ///         second invariant a paused window can break and its sibling cannot: voting
    ///         power. `_update` is overridden `(ERC20, ERC20Votes)`, so a burn under pause
    ///         must move BOTH the balance and the checkpoint — if the pause branch ever
    ///         short-circuits before the votes half, `property_votingPowerMatchesSupply`
    ///         and `property_votesTrackBalances` are what notice, and only an interleaved
    ///         sequence puts them in a position to look.
    /// @dev Entry is seed-gated for the same reason as SCC — a fair toggle would park the
    ///      campaign in a state where mint/transfer revert and every other property idles.
    function pauseToken(uint256 seed) external {
        if (seed % 4 != 0) return;
        if (sfc.paused()) return;
        vm.prank(ADMIN);
        sfc.pause();
    }

    function unpauseToken() external {
        if (!sfc.paused()) return;
        vm.prank(ADMIN);
        sfc.unpause();
    }

    // ── [CONTRACT.2] batchMint — auto-delegate + multi-element checkpoint churn ───

    /// @notice Mismatch is a deliberate MINORITY arm (three independent `% 8` lengths would
    ///         agree ~1.4% of the time and burn the campaign on a require Medusa cannot even
    ///         detect). Per-element values come from keccak(seed, i), otherwise every element
    ///         is identical and the in-batch duplicate case only ever appears trivially.
    function batchMintShaped(uint256 lenSeed, uint256 shapeSeed, uint256 seed) external {
        uint256 len = lenSeed % 8;
        uint256 aLen = len;
        uint256 cLen = len;
        uint256 mismatch = shapeSeed % 8;
        if (mismatch == 0) aLen = len + 1; // 0x32 tripwire on the length-equality require
        if (mismatch == 1) cLen = len + 1;

        (address[] memory r, uint256[] memory a, string[] memory c, uint256 total) =
            _buildBatch(len, aLen, cLen, seed, shapeSeed);

        vm.prank(MINTER);
        sfc.batchMint(r, a, c, bytes32(uint256(0xE60)));

        ghostMinted += total;
        for (uint256 i = 0; i < len; i++) {
            ghostBalance[r[i]] += a[i];
        }
    }

    /// @notice 98..102 straddles MAX_BATCH_SIZE. The payload is 98..100 — dense same-block
    ///         checkpoint churn at the production operating point — not the off-by-one arms,
    ///         which are plain reverts Medusa ignores either way.
    function batchMintAtSizeBoundary(uint256 sizeSeed, uint256 seed) external {
        uint256 len = MAX_BATCH - 2 + (sizeSeed % 5);
        (address[] memory r, uint256[] memory a, string[] memory c, uint256 total) =
            _buildBatch(len, len, len, seed, type(uint256).max);

        vm.prank(MINTER);
        sfc.batchMint(r, a, c, bytes32(uint256(0xE60)));

        ghostMinted += total;
        for (uint256 i = 0; i < len; i++) {
            ghostBalance[r[i]] += a[i];
        }
    }

    function _buildBatch(uint256 len, uint256 aLen, uint256 cLen, uint256 seed, uint256 corruptSeed)
        internal
        view
        returns (address[] memory r, uint256[] memory a, string[] memory c, uint256 total)
    {
        r = new address[](len);
        a = new uint256[](aLen);
        c = new string[](cLen);

        uint256 corrupt = corruptSeed % 16;
        uint256 victim = len == 0 ? 0 : corruptSeed % len;

        for (uint256 i = 0; i < len; i++) {
            uint256 h = uint256(keccak256(abi.encode(seed, i)));
            r[i] = _batchRecipient(h);
            if (i < aLen) {
                uint256 amt = 1 + ((h >> 8) % AMOUNT_CAP);
                if (corrupt == 0 && i == victim) amt = 0;
                a[i] = amt;
                total += amt;
            }
            if (i < cLen) {
                uint256 cidLen = 1 + ((h >> 16) % 32);
                if (corrupt == 1 && i == victim) cidLen = 0;
                if (corrupt == 2 && i == victim) cidLen = 257;
                c[i] = _cid(h, cidLen);
            }
        }
        for (uint256 i = len; i < aLen; i++) {
            a[i] = 1;
        }
        for (uint256 i = len; i < cLen; i++) {
            c[i] = "X";
        }
    }

    function _cid(uint256 h, uint256 len) internal pure returns (string memory) {
        bytes memory b = new bytes(len);
        for (uint256 j = 0; j < len; j++) {
            b[j] = bytes1(uint8(65 + ((h + j) % 26)));
        }
        return string(b);
    }

    // ── Properties ────────────────────────────────────────────────────────────

    function property_totalSupplyWithinCap() public view returns (bool) {
        return sfc.totalSupply() <= sfc.MAX_SUPPLY();
    }

    function property_solvency() public view returns (bool) {
        uint256 sum;
        for (uint256 i = 0; i < ACTORS; i++) {
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
        for (uint256 i = 0; i < ACTORS; i++) {
            votes += sfc.getVotes(actors[i]);
        }
        return votes == sfc.totalSupply();
    }

    /// @notice INV-5 [CONTRACT.2]: per-recipient attribution — the aggregates stay green if a
    ///         batch credits the right TOTAL to the wrong address.
    function property_perActorBalance() public view returns (bool) {
        for (uint256 i = 0; i < ACTORS; i++) {
            if (sfc.balanceOf(actors[i]) != ghostBalance[actors[i]]) return false;
        }
        return true;
    }

    /// @notice INV-6 [CONTRACT.2]: votes track balance PER ACTOR, not merely in aggregate.
    ///         Every actor is self-delegated — the pool from the constructor, the batch-only
    ///         pair by batchMint's auto-delegate on first receipt — so the equality is
    ///         invariant, and it catches per-element checkpoint drift that the Σ-form hides.
    function property_votesTrackBalances() public view returns (bool) {
        for (uint256 i = 0; i < ACTORS; i++) {
            if (sfc.getVotes(actors[i]) != sfc.balanceOf(actors[i])) return false;
        }
        return true;
    }
}
