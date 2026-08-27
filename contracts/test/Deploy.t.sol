// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "forge-std/Test.sol";
import "../script/Deploy.s.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title DeployWiringTest
 * @notice [SEC.1] Pins the post-deploy role matrix produced by DeploySilkenNet.deployAll —
 *         a regression guard so a swapped admin/pauser/timelock arg can never silently
 *         re-open the instant-mint (tokens) or instant-param-change (ProtocolParameters)
 *         vector. The last two tests encode the exact bypass that the admin=Timelock fix
 *         closes: under the old `admin=Safe` they would FAIL.
 * @dev deployAll is ENV-free + param-driven; the test passes `address(deploy)` as the
 *      temporary Timelock admin (deployer) so the in-contract grant/renounce calls
 *      originate from the right sender.
 */
contract DeployWiringTest is Test {
    DeploySilkenNet internal deploy;

    address internal safe = makeAddr("safe");
    address internal minter = makeAddr("minter");
    address internal slasher = makeAddr("slasher");
    address internal anchorOracle = makeAddr("anchorOracle");

    DeploySilkenNet.Deployed internal d;

    function setUp() public {
        deploy = new DeploySilkenNet();
        d = deploy.deployAll(safe, address(deploy), minter, slasher, anchorOracle);
    }

    // ─── Tokens: DEFAULT_ADMIN = Timelock, PAUSER = Safe ──────────────
    function test_tokens_adminIsTimelock_notSafe() public view {
        assertTrue(d.scc.hasRole(d.scc.DEFAULT_ADMIN_ROLE(), address(d.timelock)), "SCC admin must be Timelock");
        assertFalse(d.scc.hasRole(d.scc.DEFAULT_ADMIN_ROLE(), safe), "Safe must NOT be SCC admin");
        assertTrue(d.sfc.hasRole(d.sfc.DEFAULT_ADMIN_ROLE(), address(d.timelock)), "SFC admin must be Timelock");
        assertFalse(d.sfc.hasRole(d.sfc.DEFAULT_ADMIN_ROLE(), safe), "Safe must NOT be SFC admin");
    }

    function test_tokens_pauserIsSafe() public view {
        assertTrue(d.scc.hasRole(d.scc.PAUSER_ROLE(), safe), "SCC pauser must be Safe");
        assertTrue(d.sfc.hasRole(d.sfc.PAUSER_ROLE(), safe), "SFC pauser must be Safe");
    }

    function test_tokens_oracleRoles() public view {
        assertTrue(d.scc.hasRole(d.scc.MINTER_ROLE(), minter));
        assertTrue(d.scc.hasRole(d.scc.SLASHER_ROLE(), slasher));
        assertTrue(d.sfc.hasRole(d.sfc.MINTER_ROLE(), minter));
        assertTrue(d.sfc.hasRole(d.sfc.SLASHER_ROLE(), slasher));
    }

    // ─── [SEC.1] ProtocolParameters: admin = Timelock (NOT Safe) ──────
    function test_protocolParams_adminIsTimelock_notSafe() public view {
        assertTrue(
            d.protocolParams.hasRole(d.protocolParams.DEFAULT_ADMIN_ROLE(), address(d.timelock)),
            "Params admin must be Timelock"
        );
        assertFalse(
            d.protocolParams.hasRole(d.protocolParams.DEFAULT_ADMIN_ROLE(), safe), "Safe must NOT be Params admin"
        );
        assertTrue(
            d.protocolParams.hasRole(d.protocolParams.GOVERNANCE_ROLE(), address(d.timelock)),
            "Params governance must be Timelock"
        );
    }

    // ─── StateRootAnchor: admin = Timelock (uniform rule; ANCHOR_ROLE = oracle) ──────
    function test_anchor_adminIsTimelock_notSafe() public view {
        assertTrue(
            d.anchor.hasRole(d.anchor.DEFAULT_ADMIN_ROLE(), address(d.timelock)), "Anchor admin must be Timelock"
        );
        assertFalse(d.anchor.hasRole(d.anchor.DEFAULT_ADMIN_ROLE(), safe), "Safe must NOT be Anchor admin");
        assertTrue(d.anchor.hasRole(d.anchor.ANCHOR_ROLE(), anchorOracle));
    }

    // ─── Timelock wiring: deployer renounced; Safe + Governor wired ───
    function test_timelock_deployerRenounced() public view {
        assertFalse(
            d.timelock.hasRole(d.timelock.DEFAULT_ADMIN_ROLE(), address(deploy)),
            "deployer (temp admin) must renounce Timelock admin"
        );
        assertTrue(d.timelock.hasRole(d.timelock.DEFAULT_ADMIN_ROLE(), safe), "Safe must be Timelock admin");
    }

    // [ARCH.112] EXECUTOR_ROLE is OPEN by construction — `executors = [address(0)]`, which in
    // OZ TimelockController means `onlyRoleOrOpenRole` lets ANY address execute an operation
    // once its 48h delay has matured. This is a STANDING AUTHORITY held by the whole world,
    // and it is deliberate: a closed executor set makes a passed, matured proposal hostage to
    // one keyholder's liveness (and to their censorship), which is the failure the timelock
    // exists to prevent. The veto that makes it safe is CANCELLER (Safe + Governor), pinned
    // above — so execution being permissionless is only sound while the cancel path is real.
    //
    // Both halves are pinned, and the order matters: the DECLARATION is what a grep finds,
    // the BEHAVIOUR is what actually holds. Narrowing `executors` to a named list reds both.
    function test_timelock_executorIsOpenToAnyone() public {
        assertTrue(
            d.timelock.hasRole(d.timelock.EXECUTOR_ROLE(), address(0)),
            "EXECUTOR_ROLE must be open (address(0)): a closed set makes matured proposals hostage"
        );

        bytes memory data = "";
        bytes32 salt = keccak256("open-executor-test");
        uint256 delay = d.timelock.getMinDelay();
        address opTarget = makeAddr("openExecTarget");

        vm.prank(safe); // bootstrap PROPOSER
        d.timelock.schedule(opTarget, 0, data, bytes32(0), salt, delay);

        vm.warp(block.timestamp + delay + 1);

        // A random third party — no role, no relationship to the deploy — executes.
        address stranger = makeAddr("strangerExecutor");
        assertFalse(d.timelock.hasRole(d.timelock.EXECUTOR_ROLE(), stranger), "stranger holds no role");
        vm.prank(stranger);
        d.timelock.execute(opTarget, 0, data, bytes32(0), salt);

        bytes32 id = d.timelock.hashOperation(opTarget, 0, data, bytes32(0), salt);
        assertTrue(d.timelock.isOperationDone(id), "a role-less stranger executed the matured operation");
    }

    function test_timelock_governorAndSafeProposers() public view {
        assertTrue(d.timelock.hasRole(d.timelock.PROPOSER_ROLE(), address(d.governor)), "Governor PROPOSER");
        assertTrue(d.timelock.hasRole(d.timelock.CANCELLER_ROLE(), address(d.governor)), "Governor CANCELLER");
        assertTrue(d.timelock.hasRole(d.timelock.PROPOSER_ROLE(), safe), "Safe bootstrap PROPOSER");
        // [CONTRACT.1] Safe = guardian CANCELLER → the 48h veto window is actionable in 1 tx.
        assertTrue(d.timelock.hasRole(d.timelock.CANCELLER_ROLE(), safe), "Safe guardian CANCELLER");
    }

    // [CONTRACT.1] Guardian veto: Safe can cancel a queued Timelock operation within the 48h delay
    // (a malicious-but-passed proposal OR a compromised proposer) — the property that makes the
    // "48h gives time to organise a veto" NatSpec real.
    function test_safeGuardianCanCancelQueuedOperation() public {
        // Queue a no-op operation via the Safe (bootstrap PROPOSER).
        bytes memory data = "";
        bytes32 salt = keccak256("guardian-veto-test");
        uint256 delay = d.timelock.getMinDelay();
        address vetoTarget = makeAddr("vetoTarget");
        vm.prank(safe);
        d.timelock.schedule(vetoTarget, 0, data, bytes32(0), salt, delay);

        bytes32 id = d.timelock.hashOperation(vetoTarget, 0, data, bytes32(0), salt);
        assertTrue(d.timelock.isOperationPending(id), "queued");

        // Guardian (Safe) cancels within the window — before the delay elapses.
        vm.prank(safe);
        d.timelock.cancel(id);
        assertFalse(d.timelock.isOperation(id), "cancelled by guardian");
    }

    // ─── The bypass that #1 closes (would FAIL under the old admin=Safe) ──
    function testRevert_safeCannotSetParamsDirectly() public {
        // Safe holds no role on Params → setParameter reverts (AccessControl).
        // Read the role constant BEFORE the cheatcodes (see the note below).
        bytes32 govRole = d.protocolParams.GOVERNANCE_ROLE();
        vm.prank(safe);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, safe, govRole));
        d.protocolParams.setParameter(keccak256("dynamic_tax_rate"), 1e18);
    }

    function testRevert_safeCannotGrantItselfGovernance() public {
        // Safe is NOT Params admin → cannot grant itself GOVERNANCE_ROLE to bypass the 48h Timelock.
        // Read the role constant BEFORE the cheatcodes — an external call in the args would
        // otherwise consume the prank/expectRevert (foundry gotcha).
        bytes32 govRole = d.protocolParams.GOVERNANCE_ROLE();
        bytes32 adminRole = d.protocolParams.DEFAULT_ADMIN_ROLE(); // grantRole is admin-gated, not governance-gated
        vm.prank(safe);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, safe, adminRole)
        );
        d.protocolParams.grantRole(govRole, safe);
    }

    // ─── [SEC.1/E.2] run()-entry mainnet-safety gates under REQUIRE_SAFE_ADMIN ──
    // Pins the pre-broadcast guards so a mainnet deploy cannot silently (1) hand token/
    // timelock admin custody to an EOA, (2) hand the DAO treasury (Dynamic-Tax recipient +
    // INS.2 insurance reserve) to an EOA — reserve-adequacy against an EOA-held treasury
    // would be theatre — or (3) collapse the E.2 mint/burn key-split by granting both oracle
    // roles to one address. All cases live in ONE test: vm.setEnv is process-global and
    // Foundry runs a contract's tests in parallel, so separate tests mutating the same ENV
    // names would race each other.
    function testRevert_run_mainnetSafetyGates() public {
        vm.setEnv("REQUIRE_SAFE_ADMIN", "true");
        vm.setEnv("DAO_TREASURY_ADDRESS", vm.toString(makeAddr("eoaTreasury")));

        // (1) EOA admin → revert BEFORE any contract is deployed.
        vm.setEnv("ADMIN_ADDRESS", vm.toString(makeAddr("eoaAdmin")));
        vm.expectRevert(
            bytes("SEC.1: ADMIN_ADDRESS must be a Gnosis Safe contract (unset REQUIRE_SAFE_ADMIN for testnet EOA)")
        );
        deploy.run();

        // (2) Admin OK (a contract — the script itself) → the treasury custody-check is next.
        vm.setEnv("ADMIN_ADDRESS", vm.toString(address(deploy)));
        vm.expectRevert(
            bytes(
                "SEC.1: DAO_TREASURY_ADDRESS must be a Gnosis Safe contract (unset REQUIRE_SAFE_ADMIN for testnet EOA)"
            )
        );
        deploy.run();

        // (3) Custody OK for both → one address in both oracle roles must revert (the backend
        // guard only catches identical keys at Sidekiq boot, after the irreversible grant).
        vm.setEnv("DAO_TREASURY_ADDRESS", vm.toString(address(deploy)));
        address sharedOracle = makeAddr("sharedOracle");
        vm.setEnv("MINTER_ORACLE", vm.toString(sharedOracle));
        vm.setEnv("SLASHER_ORACLE", vm.toString(sharedOracle));
        vm.expectRevert(bytes("E.2: MINTER_ORACLE must differ from SLASHER_ORACLE (mint/burn key-split)"));
        deploy.run();
    }
}
