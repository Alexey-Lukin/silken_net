// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "forge-std/Test.sol";
import "../ProtocolParameters.sol";

/**
 * @title ProtocolParameters Test Suite
 * @notice Foundry tests for ProtocolParameters.sol — on-chain governance parameter registry.
 * @dev Covers: constructor validation, setParameter/setParameters, getters,
 *      access control (GOVERNANCE_ROLE), admin protection, events, edge cases.
 */
contract ProtocolParametersTest is Test {
    ProtocolParameters public params;

    address public admin = address(0xA);
    address public timelock = address(0xB);
    address public unauthorized = address(0xC);

    // Well-known keys (must match contract constants)
    bytes32 public constant KEY_LORENZ_SIGMA = keccak256("lorenz_sigma");
    bytes32 public constant KEY_LORENZ_RHO = keccak256("lorenz_rho");
    bytes32 public constant KEY_LORENZ_BETA = keccak256("lorenz_beta");
    bytes32 public constant KEY_EMISSION_THRESHOLD = keccak256("emission_threshold");
    bytes32 public constant KEY_SLASH_THRESHOLD = keccak256("slash_threshold");
    bytes32 public constant KEY_DYNAMIC_TAX_RATE = keccak256("dynamic_tax_rate");

    event ParameterUpdated(bytes32 indexed key, uint256 oldValue, uint256 newValue, address indexed updatedBy);

    function setUp() public {
        params = new ProtocolParameters(admin, timelock);
    }

    // ─── Constructor ──────────────────────────────────────────────────

    function test_constructor_grantsRoles() public view {
        assertTrue(params.hasRole(params.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(params.hasRole(params.GOVERNANCE_ROLE(), timelock));
    }

    function test_constructor_revertsOnZeroAdmin() public {
        vm.expectRevert("ProtocolParameters: zero admin");
        new ProtocolParameters(address(0), timelock);
    }

    function test_constructor_revertsOnZeroTimelock() public {
        vm.expectRevert("ProtocolParameters: zero timelock");
        new ProtocolParameters(admin, address(0));
    }

    // ─── setParameter ─────────────────────────────────────────────────

    function test_setParameter_setsValue() public {
        uint256 sigma = 10e18; // 10.0 in fixed-point
        vm.prank(timelock);
        params.setParameter(KEY_LORENZ_SIGMA, sigma);

        assertEq(params.getParameter(KEY_LORENZ_SIGMA), sigma);
        assertTrue(params.isParameterSet(KEY_LORENZ_SIGMA));
    }

    function test_setParameter_emitsEvent() public {
        uint256 sigma = 10e18;
        vm.prank(timelock);

        vm.expectEmit(true, true, false, true);
        emit ParameterUpdated(KEY_LORENZ_SIGMA, 0, sigma, timelock);

        params.setParameter(KEY_LORENZ_SIGMA, sigma);
    }

    function test_setParameter_emitsEventWithOldValue() public {
        uint256 oldSigma = 10e18;
        uint256 newSigma = 12e18;

        vm.startPrank(timelock);
        params.setParameter(KEY_LORENZ_SIGMA, oldSigma);

        vm.expectEmit(true, true, false, true);
        emit ParameterUpdated(KEY_LORENZ_SIGMA, oldSigma, newSigma, timelock);

        params.setParameter(KEY_LORENZ_SIGMA, newSigma);
        vm.stopPrank();
    }

    function test_setParameter_revertsOnZeroKey() public {
        vm.prank(timelock);
        vm.expectRevert("ProtocolParameters: zero key");
        params.setParameter(bytes32(0), 42);
    }

    function test_setParameter_revertsForUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        params.setParameter(KEY_LORENZ_SIGMA, 10e18);
    }

    function test_setParameter_revertsForAdmin() public {
        // Admin has DEFAULT_ADMIN_ROLE but NOT GOVERNANCE_ROLE
        vm.prank(admin);
        vm.expectRevert();
        params.setParameter(KEY_LORENZ_SIGMA, 10e18);
    }

    function test_setParameter_allowsZeroValue() public {
        // Setting a parameter to 0 should work (explicitly set to zero)
        vm.prank(timelock);
        params.setParameter(KEY_LORENZ_SIGMA, 0);

        assertEq(params.getParameter(KEY_LORENZ_SIGMA), 0);
        assertTrue(params.isParameterSet(KEY_LORENZ_SIGMA));
    }

    // ─── setParameters (batch) ────────────────────────────────────────

    function test_setParameters_batchUpdate() public {
        bytes32[] memory keys = new bytes32[](3);
        uint256[] memory values = new uint256[](3);

        keys[0] = KEY_LORENZ_SIGMA;
        values[0] = 10e18;
        keys[1] = KEY_LORENZ_RHO;
        values[1] = 28e18;
        keys[2] = KEY_LORENZ_BETA; // 8/3
        values[2] = 2666666666666666667;

        vm.prank(timelock);
        params.setParameters(keys, values);

        assertEq(params.getParameter(KEY_LORENZ_SIGMA), 10e18);
        assertEq(params.getParameter(KEY_LORENZ_RHO), 28e18);
        assertEq(params.getParameter(KEY_LORENZ_BETA), 2666666666666666667);
        assertTrue(params.isParameterSet(KEY_LORENZ_SIGMA));
        assertTrue(params.isParameterSet(KEY_LORENZ_RHO));
        assertTrue(params.isParameterSet(KEY_LORENZ_BETA));
    }

    function test_setParameters_emitsEventsForEach() public {
        bytes32[] memory keys = new bytes32[](2);
        uint256[] memory values = new uint256[](2);

        keys[0] = KEY_LORENZ_SIGMA;
        values[0] = 10e18;
        keys[1] = KEY_LORENZ_RHO;
        values[1] = 28e18;

        vm.prank(timelock);

        vm.expectEmit(true, true, false, true);
        emit ParameterUpdated(KEY_LORENZ_SIGMA, 0, 10e18, timelock);

        vm.expectEmit(true, true, false, true);
        emit ParameterUpdated(KEY_LORENZ_RHO, 0, 28e18, timelock);

        params.setParameters(keys, values);
    }

    function test_setParameters_revertsOnLengthMismatch() public {
        bytes32[] memory keys = new bytes32[](2);
        uint256[] memory values = new uint256[](3);

        vm.prank(timelock);
        vm.expectRevert("ProtocolParameters: array length mismatch");
        params.setParameters(keys, values);
    }

    function test_setParameters_revertsOnEmptyBatch() public {
        bytes32[] memory keys = new bytes32[](0);
        uint256[] memory values = new uint256[](0);

        vm.prank(timelock);
        vm.expectRevert("ProtocolParameters: empty batch");
        params.setParameters(keys, values);
    }

    function test_setParameters_revertsOnBatchTooLarge() public {
        uint256 size = params.MAX_BATCH_SIZE() + 1; // 51
        bytes32[] memory keys = new bytes32[](size);
        uint256[] memory values = new uint256[](size);

        for (uint256 i = 0; i < size; i++) {
            keys[i] = keccak256(abi.encodePacked("param_", i));
            values[i] = i;
        }

        vm.prank(timelock);
        vm.expectRevert("ProtocolParameters: batch too large");
        params.setParameters(keys, values);
    }

    function test_setParameters_revertsOnZeroKeyInBatch() public {
        bytes32[] memory keys = new bytes32[](2);
        uint256[] memory values = new uint256[](2);

        keys[0] = KEY_LORENZ_SIGMA;
        values[0] = 10e18;
        keys[1] = bytes32(0);
        values[1] = 28e18;

        vm.prank(timelock);
        vm.expectRevert("ProtocolParameters: zero key");
        params.setParameters(keys, values);
    }

    function test_setParameters_revertsForUnauthorized() public {
        bytes32[] memory keys = new bytes32[](1);
        uint256[] memory values = new uint256[](1);
        keys[0] = KEY_LORENZ_SIGMA;
        values[0] = 10e18;

        vm.prank(unauthorized);
        vm.expectRevert();
        params.setParameters(keys, values);
    }

    function test_setParameters_maxBatchSizeIs50() public view {
        assertEq(params.MAX_BATCH_SIZE(), 50);
    }

    // ─── getParameter / getParameterOrDefault / isParameterSet ────────

    function test_getParameter_returnsZeroWhenUnset() public view {
        assertEq(params.getParameter(KEY_LORENZ_SIGMA), 0);
    }

    function test_isParameterSet_falseWhenUnset() public view {
        assertFalse(params.isParameterSet(KEY_LORENZ_SIGMA));
    }

    function test_getParameterOrDefault_returnsDefaultWhenUnset() public view {
        uint256 defaultSigma = 10e18;
        assertEq(params.getParameterOrDefault(KEY_LORENZ_SIGMA, defaultSigma), defaultSigma);
    }

    function test_getParameterOrDefault_returnsValueWhenSet() public {
        uint256 sigma = 12e18;
        vm.prank(timelock);
        params.setParameter(KEY_LORENZ_SIGMA, sigma);

        // Even though default is 10e18, should return the set value 12e18
        assertEq(params.getParameterOrDefault(KEY_LORENZ_SIGMA, 10e18), sigma);
    }

    function test_getParameterOrDefault_returnsZeroWhenExplicitlySetToZero() public {
        vm.prank(timelock);
        params.setParameter(KEY_LORENZ_SIGMA, 0);

        // Parameter was explicitly set to 0. Should return 0, NOT the default.
        assertEq(params.getParameterOrDefault(KEY_LORENZ_SIGMA, 10e18), 0);
    }

    // ─── Named Getters ────────────────────────────────────────────────

    function test_namedGetter_lorenzSigma() public {
        vm.prank(timelock);
        params.setParameter(KEY_LORENZ_SIGMA, 10e18);
        assertEq(params.lorenzSigma(), 10e18);
    }

    function test_namedGetter_lorenzRho() public {
        vm.prank(timelock);
        params.setParameter(KEY_LORENZ_RHO, 28e18);
        assertEq(params.lorenzRho(), 28e18);
    }

    function test_namedGetter_lorenzBeta() public {
        uint256 beta = 2666666666666666667; // 8/3 in fixed-point 18 decimals
        vm.prank(timelock);
        params.setParameter(KEY_LORENZ_BETA, beta);
        assertEq(params.lorenzBeta(), beta);
    }

    function test_namedGetter_emissionThreshold() public {
        vm.prank(timelock);
        params.setParameter(KEY_EMISSION_THRESHOLD, 10_000e18);
        assertEq(params.emissionThreshold(), 10_000e18);
    }

    function test_namedGetter_slashThreshold() public {
        vm.prank(timelock);
        params.setParameter(KEY_SLASH_THRESHOLD, 0.2e18); // 20%
        assertEq(params.slashThreshold(), 0.2e18);
    }

    function test_namedGetter_dynamicTaxRate() public {
        vm.prank(timelock);
        params.setParameter(KEY_DYNAMIC_TAX_RATE, 0.02e18); // 2%
        assertEq(params.dynamicTaxRate(), 0.02e18);
    }

    function test_namedGetter_lorenzDt() public {
        vm.prank(timelock);
        params.setParameter(keccak256("lorenz_dt"), 0.01e18); // dt = 0.01
        assertEq(params.lorenzDt(), 0.01e18);
    }

    function test_namedGetter_lorenzIterations() public {
        vm.prank(timelock);
        params.setParameter(keccak256("lorenz_iterations"), 250e18);
        assertEq(params.lorenzIterations(), 250e18);
    }

    function test_namedGetter_lorenzZMin() public {
        vm.prank(timelock);
        params.setParameter(keccak256("lorenz_z_min"), 2e18);
        assertEq(params.lorenzZMin(), 2e18);
    }

    function test_namedGetter_lorenzZMax() public {
        vm.prank(timelock);
        params.setParameter(keccak256("lorenz_z_max"), 45e18);
        assertEq(params.lorenzZMax(), 45e18);
    }

    function test_namedGetter_lorenzZTarget() public {
        vm.prank(timelock);
        params.setParameter(keccak256("lorenz_z_target"), 29e18);
        assertEq(params.lorenzZTarget(), 29e18);
    }

    function test_namedGetter_insurancePoolThreshold() public {
        vm.prank(timelock);
        params.setParameter(keccak256("insurance_pool_threshold"), 100_000e18);
        assertEq(params.insurancePoolThreshold(), 100_000e18);
    }

    function test_namedGetter_stressThreshold() public {
        vm.prank(timelock);
        params.setParameter(keccak256("stress_threshold"), 0.3e18); // 30%
        assertEq(params.stressThreshold(), 0.3e18);
    }

    function test_namedGetter_sccPerTonneCo2() public {
        // [BIZ.1] 2000 SCC = 1 tonne CO2 — D-MRV carbon equivalence
        vm.prank(timelock);
        params.setParameter(keccak256("scc_per_tonne_co2"), 2000e18);
        assertEq(params.sccPerTonneCo2(), 2000e18);
    }

    function test_namedGetter_sccPerTonneCo2_defaultIsZero() public view {
        // Unset parameter returns 0 (use getParameterOrDefault for 2000e18 default)
        assertEq(params.sccPerTonneCo2(), 0);
    }

    function test_namedGetter_sccFallbackPriceUsdCents() public {
        // [S6.9] $25.50 = 2550 cents — governance-controlled fallback price
        vm.prank(timelock);
        params.setParameter(keccak256("scc_fallback_price_usd_cents"), 2550e18);
        assertEq(params.sccFallbackPriceUsdCents(), 2550e18);
    }

    function test_namedGetter_sccFallbackPriceUsdCents_defaultIsZero() public view {
        assertEq(params.sccFallbackPriceUsdCents(), 0);
    }

    // ─── Well-Known Key Constants ─────────────────────────────────────

    function test_keyConstants_matchSolidityKeccak() public view {
        assertEq(params.KEY_LORENZ_SIGMA(), keccak256("lorenz_sigma"));
        assertEq(params.KEY_LORENZ_RHO(), keccak256("lorenz_rho"));
        assertEq(params.KEY_LORENZ_BETA(), keccak256("lorenz_beta"));
        assertEq(params.KEY_LORENZ_DT(), keccak256("lorenz_dt"));
        assertEq(params.KEY_LORENZ_ITERATIONS(), keccak256("lorenz_iterations"));
        assertEq(params.KEY_LORENZ_Z_MIN(), keccak256("lorenz_z_min"));
        assertEq(params.KEY_LORENZ_Z_MAX(), keccak256("lorenz_z_max"));
        assertEq(params.KEY_LORENZ_Z_TARGET(), keccak256("lorenz_z_target"));
        assertEq(params.KEY_EMISSION_THRESHOLD(), keccak256("emission_threshold"));
        assertEq(params.KEY_DYNAMIC_TAX_RATE(), keccak256("dynamic_tax_rate"));
        assertEq(params.KEY_INSURANCE_POOL_THRESHOLD(), keccak256("insurance_pool_threshold"));
        assertEq(params.KEY_SLASH_THRESHOLD(), keccak256("slash_threshold"));
        assertEq(params.KEY_STRESS_THRESHOLD(), keccak256("stress_threshold"));
        assertEq(params.KEY_SCC_PER_TONNE_CO2(), keccak256("scc_per_tonne_co2"));
        assertEq(params.KEY_SCC_FALLBACK_PRICE_USD_CENTS(), keccak256("scc_fallback_price_usd_cents"));
    }

    function test_governanceRoleConstant() public view {
        assertEq(params.GOVERNANCE_ROLE(), keccak256("GOVERNANCE_ROLE"));
    }

    // ─── Admin Protection ─────────────────────────────────────────────

    function test_adminProtection_cannotRemoveLastAdmin() public {
        bytes32 adminRole = params.DEFAULT_ADMIN_ROLE();
        vm.prank(admin);
        vm.expectRevert("ProtocolParameters: cannot remove last admin");
        params.renounceRole(adminRole, admin);
    }

    function test_adminProtection_canRemoveAdminIfMultiple() public {
        bytes32 adminRole = params.DEFAULT_ADMIN_ROLE();
        address admin2 = address(0xD);

        // Admin grants admin role to admin2
        vm.prank(admin);
        params.grantRole(adminRole, admin2);

        // Now admin can renounce — there are 2 admins
        vm.prank(admin);
        params.renounceRole(adminRole, admin);

        assertFalse(params.hasRole(adminRole, admin));
        assertTrue(params.hasRole(adminRole, admin2));
    }

    function test_adminProtection_cannotRevokeLastAdmin() public {
        bytes32 adminRole = params.DEFAULT_ADMIN_ROLE();
        address admin2 = address(0xD);

        // Add second admin
        vm.prank(admin);
        params.grantRole(adminRole, admin2);

        // admin2 can revoke admin
        vm.prank(admin2);
        params.revokeRole(adminRole, admin);

        // Now admin2 is the only admin — cannot be revoked
        vm.prank(admin2);
        vm.expectRevert("ProtocolParameters: cannot remove last admin");
        params.renounceRole(adminRole, admin2);
    }

    // ─── Fuzz Tests ───────────────────────────────────────────────────

    function testFuzz_setParameter_anyValue(uint256 value) public {
        vm.prank(timelock);
        params.setParameter(KEY_LORENZ_SIGMA, value);
        assertEq(params.getParameter(KEY_LORENZ_SIGMA), value);
        assertTrue(params.isParameterSet(KEY_LORENZ_SIGMA));
    }

    function testFuzz_getParameterOrDefault_unsetReturnsDefault(uint256 defaultVal) public view {
        assertEq(params.getParameterOrDefault(KEY_LORENZ_SIGMA, defaultVal), defaultVal);
    }

    function testFuzz_setParameter_arbitraryKey(bytes32 key) public {
        vm.assume(key != bytes32(0));
        vm.prank(timelock);
        params.setParameter(key, 42e18);
        assertEq(params.getParameter(key), 42e18);
    }
}
