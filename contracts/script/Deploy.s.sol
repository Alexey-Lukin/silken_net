// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "forge-std/Script.sol";
import "../SilkenCarbonCoin.sol";
import "../SilkenForestCoin.sol";
import "../StateRootAnchor.sol";
import "../SilkenTimelock.sol";
import "../SilkenGovernor.sol";
import "../ProtocolParameters.sol";

/**
 * @title DeploySilkenNet
 * @notice Foundry deployment script for all SilkenNet smart contracts on Polygon.
 * @dev Deploys contracts in dependency order:
 *      1. SilkenTimelock — 48h governance delay (deployed FIRST so it can be the
 *         tokens' DEFAULT_ADMIN at genesis; deployer is a TEMP timelock admin)
 *      2. SilkenCarbonCoin (SCC) — utility token (admin=Timelock, pauser=Safe)
 *      3. SilkenForestCoin (SFC) — governance token (admin=Timelock, pauser=Safe)
 *      4. StateRootAnchor — L1 weekly state finalization (admin=Timelock)
 *      5. SilkenGovernor — DAO governance (depends on SFC + Timelock)
 *      6. ProtocolParameters — on-chain parameter registry (admin=Timelock, governance=Timelock)
 *      7. Post-deploy: wire Timelock roles, then hand timelock admin → Safe + renounce deployer
 *
 *      The deploy + role wiring lives in `deployAll(...)` — param-driven and ENV-free —
 *      so `test/Deploy.t.sol` can assert the exact post-deploy role matrix without ENV
 *      or broadcast. `run()` only reads ENV + wraps it in vm.broadcast. Helpers keep the
 *      stack shallow (the default profile is via_ir=false; CI runs `forge build --sizes`).
 *
 *      Usage:
 *        forge script script/Deploy.s.sol --rpc-url $RPC_URL                       # dry-run
 *        forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify  # broadcast
 *        FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
 *
 *      Required ENV:
 *        DEPLOYER_PRIVATE_KEY — private key of the deployer account (ends with NO power)
 *        ADMIN_ADDRESS        — Gnosis Safe multisig (SEC.1): token PAUSER + timelock admin
 *        MINTER_ORACLE        — backend oracle for minting (BlockchainMintingService)
 *        SLASHER_ORACLE       — backend oracle for slashing (BlockchainBurningService)
 *        ANCHOR_ORACLE        — backend oracle for L1 anchoring (EthereumAnchorWorker)
 *        DAO_TREASURY_ADDRESS — DAO treasury (Dynamic-Tax recipient + INS.2 reserve holder);
 *                               holds no on-chain role, custody-gated like ADMIN_ADDRESS
 *
 * [SEC.1] Role split: every DEFAULT_ADMIN_ROLE that gates an economic vector = the 48h
 *         Timelock. Tokens: granting any role (incl. MINTER_ROLE) carries a 48h public
 *         delay (closes instant-mint even for the multisig). ProtocolParameters: admin =
 *         Timelock too — so the Safe cannot re-grant itself GOVERNANCE_ROLE and change
 *         economic params (slash curve / dynamic tax / insurance threshold / fallback
 *         price) outside the 48h veto window, i.e. [E.35] holds as stated. PAUSER_ROLE =
 *         the Safe (instant emergency pause). StateRootAnchor admin = Timelock too — no
 *         pause() exists and granting ANCHOR_ROLE is a management power, not an emergency
 *         brake, so it is governance-gated (the 6-day MIN_ANCHOR_INTERVAL + off-chain root
 *         verification make the slower oracle-rotation a non-issue). The
 *         Safe is also a Timelock PROPOSER (bootstrap: it can schedule role grants pre-DAO,
 *         but only with the 48h delay). Production: ADMIN_ADDRESS = Gnosis Safe (3/5 or
 *         2/3) + REQUIRE_SAFE_ADMIN=true.
 * [ARCH.112] EXECUTOR_ROLE is deliberately OPEN — `executors = [address(0)]`, so once the 48h
 *         delay matures ANY address may execute. This is a standing authority held by the whole
 *         world, and it is the SAFER side of the trade: a named executor set makes a passed,
 *         matured proposal hostage to one keyholder's liveness or censorship, which is the very
 *         failure the timelock exists to prevent. The counterweight is that execution is then
 *         NOT discretionary — the only defence inside the window is CANCELLER (Safe + Governor,
 *         [CONTRACT.1]), which is why that role is load-bearing rather than a convenience.
 *         Pinned both ways by `test_timelock_executorIsOpenToAnyone` (Deploy.t.sol): the role
 *         declaration AND a role-less stranger actually executing.
 * [S3.5]  After deployment: update subgraph.yaml with the real SFC contract address.
 */
contract DeploySilkenNet is Script {
    /// @notice All deployed contract handles — returned by `deployAll` for the wiring test.
    struct Deployed {
        SilkenTimelock timelock;
        SilkenCarbonCoin scc;
        SilkenForestCoin sfc;
        StateRootAnchor anchor;
        SilkenGovernor governor;
        ProtocolParameters protocolParams;
    }

    function run() external {
        address safe = _envAddr("ADMIN_ADDRESS"); // [SEC.1] Gnosis Safe multisig
        _requireSafeOrWarn(safe, "ADMIN_ADDRESS");
        // [SEC.1] DAO treasury custody: no on-chain role, but it receives the Dynamic-Tax SCC
        // and backs the INS.2 insurance reserve — reserve-adequacy against an EOA-held
        // treasury would be theatre, so the mainnet gate checks its custody too.
        _requireSafeOrWarn(_envAddr("DAO_TREASURY_ADDRESS"), "DAO_TREASURY_ADDRESS");
        // [E.2] mint/burn key-split: the token constructors take two oracle params but never
        // assert they differ, and the backend guard (Web3NetworkGuard) only catches identical
        // keys at Sidekiq boot — AFTER the irreversible on-chain grant (48h Timelock to unwind).
        address minter = _envAddr("MINTER_ORACLE");
        address slasher = _envAddr("SLASHER_ORACLE");
        _requireDistinctOracles(minter, slasher);

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        deployAll(safe, deployer, minter, slasher, _envAddr("ANCHOR_ORACLE"));
        vm.stopBroadcast();

        console.log("");
        console.log(
            "[SEC.1] Verify: tokens+Anchor+Params DEFAULT_ADMIN=Timelock; PAUSER_ROLE=Safe; Safe=Timelock admin+PROPOSER; deployer renounced"
        );
        console.log("Post-deploy: set CARBON/FOREST/ANCHOR contract ENV; update subgraph (S3.5); verify on Polygonscan");
    }

    /// @notice Deploy + wire all contracts in dependency order. ENV-free + param-driven so
    ///         `test/Deploy.t.sol` can assert the exact post-deploy role matrix. The caller
    ///         (run() under broadcast, or the test) is the temporary Timelock admin
    ///         (`deployer`) and ends with NO roles after `_wireTimelock`.
    /// @return d Handles of every deployed contract.
    function deployAll(address safe, address deployer, address minter, address slasher, address anchorOracle)
        public
        returns (Deployed memory d)
    {
        // 1. Timelock first (deployer = TEMP admin, handed to the Safe in _wireTimelock).
        d.timelock = _deployTimelock(deployer);

        // 2-3. Tokens: admin = Timelock (grantRole, incl. MINTER, is 48h-delayed); pauser = Safe.
        d.scc = new SilkenCarbonCoin(address(d.timelock), safe, minter, slasher);
        console.log("SCC deployed at:", address(d.scc));
        d.sfc = new SilkenForestCoin(address(d.timelock), safe, minter, slasher);
        console.log("SFC deployed at:", address(d.sfc));

        // 4. StateRootAnchor — admin = Timelock (uniform "admin=Timelock except pause": the
        // contract has no pause(), and granting ANCHOR_ROLE is a management power, not an
        // emergency brake → governance-gated. The 6-day MIN_ANCHOR_INTERVAL + off-chain root
        // verification make the slower (48h) oracle-rotation a non-issue; no backend depends
        // on the admin — only ANCHOR_ROLE, set at construction.)
        d.anchor = new StateRootAnchor(address(d.timelock), anchorOracle);
        console.log("StateRootAnchor deployed at:", address(d.anchor));

        // 5-6. Governor + ProtocolParameters. [SEC.1] Params admin = Timelock (NOT the Safe):
        // setParameter is GOVERNANCE_ROLE=Timelock, and DEFAULT_ADMIN=Timelock too so the Safe
        // cannot re-grant GOVERNANCE_ROLE to itself and bypass the 48h delay on economic params.
        d.governor = new SilkenGovernor(IVotes(address(d.sfc)), d.timelock);
        console.log("SilkenGovernor deployed at:", address(d.governor));
        d.protocolParams = new ProtocolParameters(address(d.timelock), address(d.timelock));
        console.log("ProtocolParameters deployed at:", address(d.protocolParams));

        // 7. Wire Timelock roles, then hand admin → Safe + renounce deployer.
        _wireTimelock(d.timelock, address(d.governor), safe, deployer);
    }

    /// @dev Read a required, non-zero address from ENV (reverts if unset/zero).
    function _envAddr(string memory name) internal view returns (address a) {
        a = vm.envAddress(name);
        require(a != address(0), string.concat("Deploy: ", name, " not set"));
    }

    /// @dev [SEC.1] Hard-fail when `addr` (ENV `name`) has no code under REQUIRE_SAFE_ADMIN=true;
    ///      else warn (testnet EOA OK). One flag gates every custody-critical address:
    ///      ADMIN_ADDRESS + DAO_TREASURY_ADDRESS.
    function _requireSafeOrWarn(address addr, string memory name) internal view {
        if (vm.envOr("REQUIRE_SAFE_ADMIN", false)) {
            require(
                addr.code.length > 0,
                string.concat(
                    "SEC.1: ", name, " must be a Gnosis Safe contract (unset REQUIRE_SAFE_ADMIN for testnet EOA)"
                )
            );
        } else if (addr.code.length == 0) {
            console.log(
                string.concat(
                    "[SEC.1] WARNING: ",
                    name,
                    " is an EOA, not a Gnosis Safe. OK for testnet; mainnet needs a Safe + REQUIRE_SAFE_ADMIN=true."
                )
            );
        }
    }

    /// @dev [E.2] Hard-fail on a collapsed mint/burn key-split under REQUIRE_SAFE_ADMIN=true;
    ///      else warn (single-key testnet OK — the backend guard also allows it outside prod).
    function _requireDistinctOracles(address minter, address slasher) internal view {
        if (vm.envOr("REQUIRE_SAFE_ADMIN", false)) {
            require(minter != slasher, "E.2: MINTER_ORACLE must differ from SLASHER_ORACLE (mint/burn key-split)");
        } else if (minter == slasher) {
            console.log(
                "[E.2] WARNING: MINTER_ORACLE == SLASHER_ORACLE - the mint/burn key-split is collapsed. OK for testnet; mainnet needs distinct oracles."
            );
        }
    }

    /// @dev [ARCH.112] Open executor — `address(0)` means anyone may execute after the delay.
    ///      Deliberate; rationale + counterweight in the contract-level `[ARCH.112]` block above,
    ///      pin in `Deploy.t.sol#test_timelock_executorIsOpenToAnyone`. `deployer` is a temporary admin.
    function _deployTimelock(address deployer) internal returns (SilkenTimelock timelock) {
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new SilkenTimelock(proposers, executors, deployer);
        console.log("SilkenTimelock deployed at:", address(timelock));
    }

    /// @dev [SEC.1] Governor = PROPOSER+CANCELLER (DAO path). Safe = PROPOSER (bootstrap: can
    ///      schedule token grantRole(MINTER) with the 48h delay pre-DAO) + CANCELLER (guardian)
    ///      + timelock admin. Deployer renounces the timelock admin → ends with no power.
    /// @dev [CONTRACT.1] Safe holds CANCELLER_ROLE so the 48h timelock window is an ACTIONABLE
    ///      veto: a guardian can cancel a queued (malicious-but-passed OR compromised) operation
    ///      in one tx. Without it, only Governor could cancel — which needs a fresh DAO cycle
    ///      (votingDelay+period+timelock ≫ 48h), so the "48h gives time to organise a veto"
    ///      NatSpec was hollow. Safe is already Timelock admin, so this grants no new ultimate
    ///      power (it could self-grant CANCELLER anyway) — it just makes the guardian path a
    ///      documented 1-tx action instead of an undocumented 2-tx one.
    function _wireTimelock(SilkenTimelock timelock, address governor, address safe, address deployer) internal {
        timelock.grantRole(timelock.PROPOSER_ROLE(), governor);
        timelock.grantRole(timelock.CANCELLER_ROLE(), governor);
        timelock.grantRole(timelock.PROPOSER_ROLE(), safe);
        timelock.grantRole(timelock.CANCELLER_ROLE(), safe);
        timelock.grantRole(timelock.DEFAULT_ADMIN_ROLE(), safe);
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);
        console.log(
            "Timelock wired: Governor PROPOSER+CANCELLER, Safe PROPOSER(bootstrap)+CANCELLER(guardian)+admin; deployer renounced"
        );
    }
}
