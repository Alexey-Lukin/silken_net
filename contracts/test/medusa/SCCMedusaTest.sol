// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "../../SilkenCarbonCoin.sol";

/**
 * @title SCCMedusaTest
 * @notice Medusa property-fuzzing harness for SCC. Medusa has no `targetContract()` routing,
 *         so the handler (wrapper calls + ghost accounting) and the `property_*` checks live
 *         in ONE contract. Mirrors test/invariant/SCCInvariants.t.sol but with bool-returning
 *         `property_` functions (checked after every call sequence). `vm.prank` is reached via
 *         the HEVM cheatcode address (Medusa supports it); bounds use `%` (no forge-std dep).
 *         Canon: docs/05_03 §Smart Contract Audit Roadmap (tool: crytic/medusa).
 *
 *         [CONTRACT.2] `batchMint` — the PRODUCTION mint path (the Ruby layer batches
 *         per-dispatch and the binary-search poisoned-record isolation is built around it) —
 *         had ZERO fuzz coverage: no wrapper drove it, so no property ever saw a multi-element
 *         transition, an in-batch duplicate recipient, or same-block checkpoint churn.
 *
 *         Honest framing of the two channels this adds, because they are NOT equal:
 *           · PROPERTY channel = the real payload (multi-element state transitions).
 *           · PANIC channel    = a regression TRIPWIRE on exactly one guard. Of the six panic
 *             codes enabled in medusa-scc.json, four have no corresponding language construct
 *             anywhere in the reachable graph (no `enum`, no `.pop(`, no storage bytes/string,
 *             no function-pointer variable) and 0x41 needs a ~2^64 length. Only 0x32
 *             (out-of-bounds array access) has a live construct — the `amounts[i]`/`treeDids[i]`
 *             indexing in batchMint's loops — silenced by the single length-equality require.
 *             Weaken that require and the mismatch arm below trips 0x32 immediately, before any
 *             mint. That is the whole panic-channel value; it is not a hunter.
 *
 *         Two coupled decisions, do not break one without the other:
 *           · Panics are NOT caught. Medusa inspects only the TOP-LEVEL result of each call;
 *             a try/catch'd Panic makes the outer call succeed and becomes invisible.
 *           · Ghost accounting is summed from the INPUT amounts, never from a totalSupply
 *             delta (that would make property_supplyAccounting a tautology). It is atomic
 *             ONLY because there is no catch: a reverting batchMint rolls the ghost back too.
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

    /// @dev [0..3] general pool (mint/slash/transfer); [4..5] batch-only recipients — kept out
    ///      of the transfer/mint pool so the SFC sibling's auto-delegate branch has a genuinely
    ///      fresh address to fire on. Symmetric here so both harnesses read the same.
    uint256 internal constant POOL = 4;
    uint256 internal constant ACTORS = 6;
    address[ACTORS] internal actors;

    uint256 public ghostMinted;
    uint256 public ghostSlashed;
    /// @dev Per-actor ghost — the aggregate properties are blind to "right total, wrong
    ///      recipient", and a batch is exactly where such a permutation bug would live.
    mapping(address => uint256) public ghostBalance;

    /// @dev Per-element amount ceiling. Deliberately small (1e21 ≈ 1000 SCC): with ≤102
    ///      elements a batch tops out ~1e23, far under either cap, so calls explore the mint
    ///      path instead of dying on "cap exceeded" — and it keeps the ghost sum far from
    ///      overflowing (an overflow in OUR arithmetic is panic 0x11, which is off by config).
    uint256 internal constant AMOUNT_CAP = 1e21;
    uint256 internal constant MAX_BATCH = 100; // mirrors SilkenCarbonCoin.MAX_BATCH_SIZE

    constructor() {
        scc = new SilkenCarbonCoin(ADMIN, ADMIN, MINTER, SLASHER);
        actors[0] = address(0x2001);
        actors[1] = address(0x2002);
        actors[2] = address(0x2003);
        actors[3] = address(0x2004);
        actors[4] = address(0x2005);
        actors[5] = address(0x2006);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % POOL];
    }

    function _batchRecipient(uint256 seed) internal view returns (address) {
        return actors[seed % ACTORS];
    }

    // ── Wrapper calls the fuzzer drives (always-valid, role-correct) ──────────

    function mint(uint256 actorSeed, uint256 amount) external {
        uint256 remaining = scc.MAX_SUPPLY() - scc.totalSupply();
        if (remaining == 0) return;
        amount = (amount % remaining) + 1; // [1, remaining] → never exceeds cap
        address to = _actor(actorSeed);
        vm.prank(MINTER);
        scc.mint(to, amount, "MEDUSA-INV", bytes32(uint256(0xE60)));
        ghostMinted += amount;
        ghostBalance[to] += amount;
    }

    function slash(uint256 actorSeed, uint256 amount) external {
        address from = _actor(actorSeed);
        uint256 bal = scc.balanceOf(from);
        if (bal == 0) return;
        amount = (amount % bal) + 1; // [1, bal]
        vm.prank(SLASHER);
        scc.slash(from, amount);
        ghostSlashed += amount;
        ghostBalance[from] -= amount;
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
        uint256 slashed = scc.slashUpTo(from, maxAmount, bytes32(0));
        ghostSlashed += slashed;
        ghostBalance[from] -= slashed;
    }

    function transferTokens(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = scc.balanceOf(from);
        if (bal == 0) return;
        amount = amount % (bal + 1); // [0, bal]
        vm.prank(from);
        scc.transfer(to, amount);
        if (from != to) {
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
        }
    }

    // ── [CONTRACT.2] pause / unpause — B-07 INSIDE a sequence ────────────────

    /// @notice B-07 says `slash()` must never be blocked by `pause()`. That invariant is
    ///         already proven in isolation — a unit test and, stronger, a Halmos symbolic
    ///         proof over all balances. What NO layer covered is the invariant holding
    ///         through an arbitrary INTERLEAVING (mint → pause → slash → unpause →
    ///         transfer): the Foundry invariant harnesses exclude pause by construction
    ///         (`pauser=admin`, no wrapper), and this file had no pause surface at all.
    ///         Adding it here is the only place the accounting properties get to observe a
    ///         paused window, and the accounting is exactly what a pause can corrupt: under
    ///         `_update` a burn passes while mint/transfer revert, so a bookkeeping bug
    ///         would show up as ghost drift, not as a failed call.
    /// @dev Pause is deliberately made RARE rather than a fair coin. A bare toggle pair
    ///      settles at ~50% of the campaign spent in a state where mint/transfer revert —
    ///      i.e. it would buy this invariant by halving coverage of every other one. The
    ///      seed gate makes entry ~1/4 of this handler's calls while exit stays ungated, so
    ///      the chain sits in a paused window roughly a fifth of the time and every window
    ///      is short enough to be re-entered many times per sequence.
    function pauseToken(uint256 seed) external {
        if (seed % 4 != 0) return;
        if (scc.paused()) return;
        vm.prank(ADMIN);
        scc.pause();
    }

    function unpauseToken() external {
        if (!scc.paused()) return;
        vm.prank(ADMIN);
        scc.unpause();
    }

    // ── [CONTRACT.2] batchMint — the production mint path ─────────────────────

    /// @notice The fuzzer owns the SHAPE. Three lengths are derived from one base so that
    ///         mismatch is a deliberate MINORITY arm rather than the default: three fully
    ///         independent `% 8` lengths agree only ~1.4% of the time, which would burn the
    ///         whole campaign budget on a require that unit tests already pin and that Medusa
    ///         cannot detect anyway. Here ~3/4 of calls are well-shaped.
    /// @dev Per-element values are derived with keccak(seed, i) — one seed for the whole batch
    ///      would make every element identical (one recipient, one amount, one DID), and the
    ///      duplicate-recipient case we care about would only ever appear in its trivial form.
    ///      Elements are valid BY CONSTRUCTION, with an explicit minority arm that corrupts
    ///      exactly ONE of them: under a uniform keccak distribution a zero amount or a
    ///      257-byte DID is otherwise unreachable (p ≈ 1e-24), so the per-element guards would
    ///      never be exercised at all.
    function batchMintShaped(uint256 lenSeed, uint256 shapeSeed, uint256 seed) external {
        uint256 len = lenSeed % 8; // 0 → exercises `require(length > 0)`
        uint256 aLen = len;
        uint256 dLen = len;
        uint256 mismatch = shapeSeed % 8;
        if (mismatch == 0) aLen = len + 1; // 0x32 tripwire: only the length require stops it
        if (mismatch == 1) dLen = len + 1;

        (address[] memory r, uint256[] memory a, string[] memory d, uint256 total) =
            _buildBatch(len, aLen, dLen, seed, shapeSeed);

        vm.prank(MINTER);
        scc.batchMint(r, a, d, bytes32(uint256(0xE60)));

        // Only reached on success — a revert rolls this back with the mint (no catch, by design).
        ghostMinted += total;
        for (uint256 i = 0; i < len; i++) {
            ghostBalance[r[i]] += a[i];
        }
    }

    /// @notice Straddles MAX_BATCH_SIZE (98..102). The 101/102 arms carry no detection value on
    ///         their own — an off-by-one either way is a plain revert Medusa ignores. The payload
    ///         is 98..100: dense same-block state churn and supply accounting AT SCALE, which is
    ///         also the production operating point (the backend's OPTIMAL_BATCH_SIZE == 100).
    function batchMintAtSizeBoundary(uint256 sizeSeed, uint256 seed) external {
        uint256 len = MAX_BATCH - 2 + (sizeSeed % 5); // 98..102
        (address[] memory r, uint256[] memory a, string[] memory d, uint256 total) =
            _buildBatch(len, len, len, seed, type(uint256).max); // no corrupt arm at this size

        vm.prank(MINTER);
        scc.batchMint(r, a, d, bytes32(uint256(0xE60)));

        ghostMinted += total;
        for (uint256 i = 0; i < len; i++) {
            ghostBalance[r[i]] += a[i];
        }
    }

    function _buildBatch(uint256 len, uint256 aLen, uint256 dLen, uint256 seed, uint256 corruptSeed)
        internal
        view
        returns (address[] memory r, uint256[] memory a, string[] memory d, uint256 total)
    {
        r = new address[](len);
        a = new uint256[](aLen);
        d = new string[](dLen);

        // Corrupt exactly ONE element (minority arm) so each per-element guard is reachable.
        uint256 corrupt = corruptSeed % 16;
        uint256 victim = len == 0 ? 0 : corruptSeed % len;

        for (uint256 i = 0; i < len; i++) {
            uint256 h = uint256(keccak256(abi.encode(seed, i)));
            r[i] = _batchRecipient(h);
            if (i < aLen) {
                uint256 amt = 1 + ((h >> 8) % AMOUNT_CAP);
                if (corrupt == 0 && i == victim) amt = 0; // require(amounts[i] > 0)
                a[i] = amt;
                total += amt;
            }
            if (i < dLen) {
                uint256 didLen = 1 + ((h >> 16) % 32);
                if (corrupt == 1 && i == victim) didLen = 0; // require(didLen > 0)
                if (corrupt == 2 && i == victim) didLen = 257; // require(didLen <= 256)
                d[i] = _did(h, didLen);
            }
        }
        // Surplus slots of a mismatched array still need well-formed content.
        for (uint256 i = len; i < aLen; i++) {
            a[i] = 1;
        }
        for (uint256 i = len; i < dLen; i++) {
            d[i] = "X";
        }
    }

    function _did(uint256 h, uint256 len) internal pure returns (string memory) {
        bytes memory b = new bytes(len);
        for (uint256 j = 0; j < len; j++) {
            b[j] = bytes1(uint8(65 + ((h + j) % 26)));
        }
        return string(b);
    }

    // ── Properties (Medusa checks these return true after every call) ─────────

    /// @notice INV-1: hard cap is never breached.
    function property_totalSupplyWithinCap() public view returns (bool) {
        return scc.totalSupply() <= scc.MAX_SUPPLY();
    }

    /// @notice INV-2: solvency — Σ actor balances == totalSupply (tokens only ever live here).
    /// @dev Sums ALL actors incl. the batch-only pool: every recipient the harness can reach
    ///      must be inside this sum, or a legitimate batch would read as insolvency.
    function property_solvency() public view returns (bool) {
        uint256 sum;
        for (uint256 i = 0; i < ACTORS; i++) {
            sum += scc.balanceOf(actors[i]);
        }
        return sum == scc.totalSupply();
    }

    /// @notice INV-3: totalSupply == minted − slashed.
    function property_supplyAccounting() public view returns (bool) {
        return scc.totalSupply() == ghostMinted - ghostSlashed;
    }

    /// @notice INV-5 [CONTRACT.2]: per-recipient attribution. The aggregate invariants above all
    ///         stay green if a batch credits the right TOTAL to the wrong address (a permutation
    ///         bug — `_mint(recipients[i], amounts[j])`), which is precisely the class a
    ///         multi-element batch opens up.
    function property_perActorBalance() public view returns (bool) {
        for (uint256 i = 0; i < ACTORS; i++) {
            if (scc.balanceOf(actors[i]) != ghostBalance[actors[i]]) return false;
        }
        return true;
    }
}
