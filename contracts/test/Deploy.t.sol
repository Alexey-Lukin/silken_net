// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "forge-std/Test.sol";
import "../script/Deploy.s.sol";

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

    address internal safe = address(0x5AFE);
    address internal minter = address(0x111);
    address internal slasher = address(0x222);
    address internal anchorOracle = address(0x333);

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

    function test_timelock_governorAndSafeProposers() public view {
        assertTrue(d.timelock.hasRole(d.timelock.PROPOSER_ROLE(), address(d.governor)), "Governor PROPOSER");
        assertTrue(d.timelock.hasRole(d.timelock.CANCELLER_ROLE(), address(d.governor)), "Governor CANCELLER");
        assertTrue(d.timelock.hasRole(d.timelock.PROPOSER_ROLE(), safe), "Safe bootstrap PROPOSER");
    }

    // ─── The bypass that #1 closes (would FAIL under the old admin=Safe) ──
    function test_safeCannotSetParamsDirectly() public {
        // Safe holds no role on Params → setParameter reverts (AccessControl).
        vm.prank(safe);
        vm.expectRevert();
        d.protocolParams.setParameter(keccak256("dynamic_tax_rate"), 1e18);
    }

    function test_safeCannotGrantItselfGovernance() public {
        // Safe is NOT Params admin → cannot grant itself GOVERNANCE_ROLE to bypass the 48h Timelock.
        // Read the role constant BEFORE the cheatcodes — an external call in the args would
        // otherwise consume the prank/expectRevert (foundry gotcha).
        bytes32 govRole = d.protocolParams.GOVERNANCE_ROLE();
        vm.prank(safe);
        vm.expectRevert();
        d.protocolParams.grantRole(govRole, safe);
    }
}
