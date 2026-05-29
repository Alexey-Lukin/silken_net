// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "../SilkenCarbonCoin.sol";
import "../SilkenForestCoin.sol";
import "../StateRootAnchor.sol";
import "../SilkenTimelock.sol";
import "../SilkenGovernor.sol";
import "../ProtocolParameters.sol";

/**
 * @title DeploySilkenNet
 * @notice Foundry deployment script for all Gaia 2.0 smart contracts on Polygon.
 * @dev Deploys contracts in dependency order:
 *      1. SilkenCarbonCoin (SCC) — utility token
 *      2. SilkenForestCoin (SFC) — governance token
 *      3. StateRootAnchor — L1 weekly state finalization
 *      4. SilkenTimelock — 48h governance delay
 *      5. SilkenGovernor — DAO governance (depends on SFC + Timelock)
 *      6. ProtocolParameters — on-chain parameter registry (governed by Timelock)
 *      7. Post-deploy: grant Governor roles on Timelock
 *
 *      Usage:
 *        # Dry-run (simulation):
 *        forge script script/Deploy.s.sol --rpc-url $RPC_URL
 *
 *        # Broadcast to network:
 *        forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
 *
 *        # With production profile (max optimization):
 *        FOUNDRY_PROFILE=production forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
 *
 *      Required ENV:
 *        DEPLOYER_PRIVATE_KEY — private key of the deployer account
 *        ADMIN_ADDRESS        — multisig admin (recommended: Gnosis Safe, see SEC.1)
 *        MINTER_ORACLE        — backend oracle for minting (BlockchainMintingService)
 *        SLASHER_ORACLE       — backend oracle for slashing (BlockchainBurningService)
 *        ANCHOR_ORACLE        — backend oracle for L1 anchoring (EthereumAnchorWorker)
 *
 * [SEC.1] Production: ADMIN_ADDRESS should be Gnosis Safe multisig (3/5 or 2/3).
 * [S3.5]  After deployment: update subgraph.yaml with real SFC contract address.
 */
contract DeploySilkenNet is Script {
    function run() external {
        // ─── Read ENV ─────────────────────────────────────────────────
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address minterOracle = vm.envAddress("MINTER_ORACLE");
        address slasherOracle = vm.envAddress("SLASHER_ORACLE");
        address anchorOracle = vm.envAddress("ANCHOR_ORACLE");

        require(admin != address(0), "Deploy: ADMIN_ADDRESS not set");
        require(minterOracle != address(0), "Deploy: MINTER_ORACLE not set");
        require(slasherOracle != address(0), "Deploy: SLASHER_ORACLE not set");
        require(anchorOracle != address(0), "Deploy: ANCHOR_ORACLE not set");

        // [SEC.1] Admin must be a Gnosis Safe multisig (a contract), not an EOA. Nothing is
        // deployed yet, so admin is set correctly at genesis — no later role migration needed.
        // REQUIRE_SAFE_ADMIN=true hard-enforces (mainnet); default only warns (testnet/local EOA OK).
        if (vm.envOr("REQUIRE_SAFE_ADMIN", false)) {
            require(
                admin.code.length > 0,
                "SEC.1: ADMIN_ADDRESS must be a Gnosis Safe contract (unset REQUIRE_SAFE_ADMIN for testnet EOA)"
            );
        } else if (admin.code.length == 0) {
            console.log("[SEC.1] WARNING: ADMIN is an EOA, not a Gnosis Safe. OK for testnet; for mainnet set a Safe + REQUIRE_SAFE_ADMIN=true.");
        }

        vm.startBroadcast(deployerKey);

        // ─── 1. SilkenCarbonCoin (SCC) ────────────────────────────────
        SilkenCarbonCoin scc = new SilkenCarbonCoin(admin, minterOracle, slasherOracle);
        console.log("SCC deployed at:", address(scc));

        // ─── 2. SilkenForestCoin (SFC) ────────────────────────────────
        SilkenForestCoin sfc = new SilkenForestCoin(admin, minterOracle, slasherOracle);
        console.log("SFC deployed at:", address(sfc));

        // ─── 3. StateRootAnchor ───────────────────────────────────────
        StateRootAnchor anchor = new StateRootAnchor(admin, anchorOracle);
        console.log("StateRootAnchor deployed at:", address(anchor));

        // ─── 4. SilkenTimelock (48h min delay) ───────────────────────
        // Governor will be added as proposer after deployment.
        // Anyone can execute after delay (address(0) = open executor).
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        SilkenTimelock timelock = new SilkenTimelock(proposers, executors, admin);
        console.log("SilkenTimelock deployed at:", address(timelock));

        // ─── 5. SilkenGovernor ────────────────────────────────────────
        SilkenGovernor governor = new SilkenGovernor(
            IVotes(address(sfc)),
            timelock
        );
        console.log("SilkenGovernor deployed at:", address(governor));

        // ─── 6. ProtocolParameters ────────────────────────────────────
        ProtocolParameters protocolParams = new ProtocolParameters(admin, address(timelock));
        console.log("ProtocolParameters deployed at:", address(protocolParams));

        // ─── 7. Post-deploy: Grant Governor roles on Timelock ─────────
        // Governor needs PROPOSER_ROLE and CANCELLER_ROLE on the Timelock
        // to queue and cancel governance proposals.
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        console.log("Governor granted PROPOSER + CANCELLER roles on Timelock");

        vm.stopBroadcast();

        // ─── Summary ─────────────────────────────────────────────────
        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("SCC:", address(scc));
        console.log("SFC:", address(sfc));
        console.log("StateRootAnchor:", address(anchor));
        console.log("SilkenTimelock:", address(timelock));
        console.log("SilkenGovernor:", address(governor));
        console.log("ProtocolParameters:", address(protocolParams));
        console.log("");
        console.log("=== Post-Deploy Checklist ===");
        console.log("1. Set CARBON_COIN_CONTRACT_ADDRESS =", address(scc));
        console.log("2. Set FOREST_COIN_CONTRACT_ADDRESS =", address(sfc));
        console.log("3. Set ETHEREUM_ANCHOR_CONTRACT =", address(anchor));
        console.log("4. Update subgraph.yaml with SFC address (S3.5)");
        console.log("5. Verify contracts on Polygonscan");
        console.log("6. [SEC.1] Verify admin = Gnosis Safe (set at deploy; use REQUIRE_SAFE_ADMIN=true on mainnet)");
    }
}
