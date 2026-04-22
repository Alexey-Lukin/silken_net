// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ProtocolParameters
 * @notice On-chain registry для параметрів протоколу Gaia 2.0.
 * @dev Зберігає ключові константи екосистеми (Lorenz attractor, tokenomics, slashing thresholds)
 *      як uint256 з 18 decimals fixed-point (1e18 = 1.0). Параметри змінюються ТІЛЬКИ через
 *      governance pipeline: SilkenGovernor → SilkenTimelock (48h) → ProtocolParameters.
 *
 *      Backend (Rails) зчитує параметри через Governance::ParameterSyncWorker
 *      (1×/день, queue: web3_low) і зберігає у SystemParameter model.
 *
 *      Значення зберігаються як uint256 з 18 decimals (аналогічно ERC-20 wei).
 *      Наприклад: σ = 10.0 → 10_000000000000000000 (10 * 1e18)
 *
 * [ARCH.4] Governance DAO — protocol constants via on-chain governance.
 * [E.35]   Flash Loan defense — параметри змінюються тільки через Timelock (48h delay).
 *
 * @custom:security-contact security@silkennet.io
 */
contract ProtocolParameters is AccessControl {

    /// @notice Роль для оновлення параметрів. Призначається SilkenTimelock.
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    /// @dev Лічильник адміністраторів для запобігання видаленню останнього DEFAULT_ADMIN_ROLE.
    uint256 private _adminCount;

    /// @dev Generic key-value store для всіх параметрів.
    mapping(bytes32 => uint256) private _parameters;

    /// @dev Tracking which parameters have been explicitly set (to distinguish 0 from unset).
    mapping(bytes32 => bool) private _parameterSet;

    // ─── Well-Known Parameter Keys ────────────────────────────────────
    // Lorenz attractor
    bytes32 public constant KEY_LORENZ_SIGMA = keccak256("lorenz_sigma");
    bytes32 public constant KEY_LORENZ_RHO = keccak256("lorenz_rho");
    bytes32 public constant KEY_LORENZ_BETA = keccak256("lorenz_beta");
    bytes32 public constant KEY_LORENZ_DT = keccak256("lorenz_dt");
    bytes32 public constant KEY_LORENZ_ITERATIONS = keccak256("lorenz_iterations");
    bytes32 public constant KEY_LORENZ_Z_MIN = keccak256("lorenz_z_min");
    bytes32 public constant KEY_LORENZ_Z_MAX = keccak256("lorenz_z_max");
    bytes32 public constant KEY_LORENZ_Z_TARGET = keccak256("lorenz_z_target");

    // Tokenomics
    bytes32 public constant KEY_EMISSION_THRESHOLD = keccak256("emission_threshold");
    bytes32 public constant KEY_DYNAMIC_TAX_RATE = keccak256("dynamic_tax_rate");
    bytes32 public constant KEY_INSURANCE_POOL_THRESHOLD = keccak256("insurance_pool_threshold");

    // Slashing
    bytes32 public constant KEY_SLASH_THRESHOLD = keccak256("slash_threshold");
    bytes32 public constant KEY_STRESS_THRESHOLD = keccak256("stress_threshold");

    /// @notice Емітується при зміні будь-якого параметра.
    /// @param key Keccak256 хеш назви параметра.
    /// @param oldValue Попереднє значення (0 якщо раніше не встановлювалось).
    /// @param newValue Нове значення (uint256, 18 decimals fixed-point).
    /// @param updatedBy Адреса, що ініціювала зміну (зазвичай Timelock).
    event ParameterUpdated(
        bytes32 indexed key,
        uint256 oldValue,
        uint256 newValue,
        address indexed updatedBy
    );

    /// @notice Конструктор ProtocolParameters.
    /// @param admin Адміністратор контракту (DEFAULT_ADMIN_ROLE). Рекомендовано: Gnosis Safe multisig.
    /// @param timelock Адреса SilkenTimelock (GOVERNANCE_ROLE). Всі зміни параметрів через governance.
    constructor(address admin, address timelock) {
        require(admin != address(0), "ProtocolParameters: zero admin");
        require(timelock != address(0), "ProtocolParameters: zero timelock");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNANCE_ROLE, timelock);
    }

    // ─── Generic Parameter API ────────────────────────────────────────

    /// @notice Встановлення параметра за ключем. Тільки через governance (Timelock).
    /// @param key Keccak256 хеш назви параметра.
    /// @param value Нове значення (uint256, 18 decimals fixed-point).
    function setParameter(bytes32 key, uint256 value) external onlyRole(GOVERNANCE_ROLE) {
        require(key != bytes32(0), "ProtocolParameters: zero key");
        uint256 oldValue = _parameters[key];
        _parameters[key] = value;
        _parameterSet[key] = true;
        emit ParameterUpdated(key, oldValue, value, msg.sender);
    }

    /// @notice Максимальна кількість параметрів у batch-оновленні для gas safety.
    uint256 public constant MAX_BATCH_SIZE = 50;

    /// @notice Batch-оновлення кількох параметрів в одній транзакції.
    /// @param keys Масив ключів параметрів.
    /// @param values Масив нових значень.
    function setParameters(bytes32[] calldata keys, uint256[] calldata values) external onlyRole(GOVERNANCE_ROLE) {
        require(keys.length == values.length, "ProtocolParameters: array length mismatch");
        require(keys.length > 0, "ProtocolParameters: empty batch");
        require(keys.length <= MAX_BATCH_SIZE, "ProtocolParameters: batch too large");

        for (uint256 i = 0; i < keys.length; i++) {
            require(keys[i] != bytes32(0), "ProtocolParameters: zero key");
            uint256 oldValue = _parameters[keys[i]];
            _parameters[keys[i]] = values[i];
            _parameterSet[keys[i]] = true;
            emit ParameterUpdated(keys[i], oldValue, values[i], msg.sender);
        }
    }

    /// @notice Зчитування параметра за ключем.
    /// @param key Keccak256 хеш назви параметра.
    /// @return value Поточне значення (0 якщо не встановлено).
    function getParameter(bytes32 key) external view returns (uint256) {
        return _parameters[key];
    }

    /// @notice Зчитування параметра з fallback-значенням для невстановлених параметрів.
    /// @dev Усуває неоднозначність "значення 0" vs "параметр не встановлено".
    ///      Frontend, subgraph та ParameterSyncWorker повинні використовувати цей метод.
    /// @param key Keccak256 хеш назви параметра.
    /// @param defaultValue Значення за замовчуванням, якщо параметр не встановлено.
    /// @return value Поточне значення або defaultValue.
    function getParameterOrDefault(bytes32 key, uint256 defaultValue) external view returns (uint256) {
        if (_parameterSet[key]) {
            return _parameters[key];
        }
        return defaultValue;
    }

    /// @notice Перевірка чи параметр був явно встановлений.
    /// @param key Keccak256 хеш назви параметра.
    /// @return true якщо параметр встановлено через governance.
    function isParameterSet(bytes32 key) external view returns (bool) {
        return _parameterSet[key];
    }

    // ─── Named Getters (convenience) ──────────────────────────────────

    /// @notice Параметр σ (sigma) атрактора Лоренца. Default: 10.0 (10e18).
    function lorenzSigma() external view returns (uint256) {
        return _parameters[KEY_LORENZ_SIGMA];
    }

    /// @notice Параметр ρ (rho) атрактора Лоренца. Default: 28.0 (28e18).
    function lorenzRho() external view returns (uint256) {
        return _parameters[KEY_LORENZ_RHO];
    }

    /// @notice Параметр β (beta) атрактора Лоренца. Default: 8/3 ≈ 2.666... (2666666666666666667).
    function lorenzBeta() external view returns (uint256) {
        return _parameters[KEY_LORENZ_BETA];
    }

    /// @notice Поріг growth_points для мінтингу 1 SCC. Default: 10000 (10000e18).
    function emissionThreshold() external view returns (uint256) {
        return _parameters[KEY_EMISSION_THRESHOLD];
    }

    /// @notice Поріг відсотка аномальних дерев для активації slashing. Default: 0.20 (0.2e18).
    function slashThreshold() external view returns (uint256) {
        return _parameters[KEY_SLASH_THRESHOLD];
    }

    /// @notice Ставка Dynamic Tax до DAO Treasury. Default: 0.02 (0.02e18).
    function dynamicTaxRate() external view returns (uint256) {
        return _parameters[KEY_DYNAMIC_TAX_RATE];
    }

    // ─── Admin Protection ─────────────────────────────────────────────

    /// @dev Захист від видалення останнього DEFAULT_ADMIN_ROLE.
    function _grantRole(bytes32 role, address account) internal override returns (bool) {
        bool granted = super._grantRole(role, account);
        if (granted && role == DEFAULT_ADMIN_ROLE) {
            _adminCount++;
        }
        return granted;
    }

    /// @dev Блокує видалення останнього адміна через renounceRole або revokeRole.
    function _revokeRole(bytes32 role, address account) internal override returns (bool) {
        if (role == DEFAULT_ADMIN_ROLE) {
            require(_adminCount > 1, "ProtocolParameters: cannot remove last admin");
        }
        bool revoked = super._revokeRole(role, account);
        if (revoked && role == DEFAULT_ADMIN_ROLE) {
            _adminCount--;
        }
        return revoked;
    }
}
