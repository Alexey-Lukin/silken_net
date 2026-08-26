// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ProtocolParameters
 * @notice On-chain registry для параметрів протоколу SilkenNet.
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
    // Lorenz attractor — ⚠️ [GOV.1] DCI-locked: бекенд НАВМИСНО не синхронізує ці ключі.
    // Константи Лоренца биті-в-біт спільні між прошитим firmware (mruby) і сервером (FW.7);
    // зміна = координований reflash усього флоту, НЕ DAO-голос. Reserved для майбутньої
    // OTA-ери: setParameter їх приймає, але ефект на протокол сьогодні нульовий
    // (Governance::ParameterSyncWorker свідомо їх не тягне — див. docs/05_06 §7).
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

    // Carbon accounting (D-MRV equivalence — BIZ.1)
    bytes32 public constant KEY_SCC_PER_TONNE_CO2 = keccak256("scc_per_tonne_co2");

    // Slashing
    bytes32 public constant KEY_SLASH_THRESHOLD = keccak256("slash_threshold");
    bytes32 public constant KEY_STRESS_THRESHOLD = keccak256("stress_threshold");

    // Slashing curve (05_05 §3 — convex penalty; споживач: BlockchainBurningService) [GOV.1]
    bytes32 public constant KEY_SLASH_GAMMA = keccak256("slash_gamma");
    bytes32 public constant KEY_SLASH_PENALTY_FACTOR_MAX = keccak256("slash_penalty_factor_max");

    // ⛔ Ціни SCC серед well-known ключів НЕМАЄ, і це не пропуск: протокол курсу не
    // тримає (00_04 §3 «не зафіксовано»), а бекенд не має жодного цінового читача.
    // Ключ без читача = DAO-ручка, якою нікому крутити (гейт ARCH.104). Зʼявиться
    // реальний споживач ціни — тоді й ключ, разом із ним.

    /// @notice Емітується при зміні будь-якого параметра.
    /// @param key Keccak256 хеш назви параметра.
    /// @param oldValue Попереднє значення (0 якщо раніше не встановлювалось).
    /// @param newValue Нове значення (uint256, 18 decimals fixed-point).
    /// @param updatedBy Адреса, що ініціювала зміну (зазвичай Timelock).
    event ParameterUpdated(bytes32 indexed key, uint256 oldValue, uint256 newValue, address indexed updatedBy);

    /// @notice Конструктор ProtocolParameters.
    /// @param admin Адміністратор ролей (DEFAULT_ADMIN_ROLE). [SEC.1] production = SilkenTimelock
    ///        (НЕ Gnosis Safe): інакше admin міг би `grantRole(GOVERNANCE_ROLE, self)` і змінити
    ///        параметри в обхід 48h-Timelock — підрив [E.35]. Безпечно = той самий Timelock, що і timelock.
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

    /// @notice Крок інтегрування dt атрактора Лоренца. Default: 0.01 (0.01e18).
    function lorenzDt() external view returns (uint256) {
        return _parameters[KEY_LORENZ_DT];
    }

    /// @notice Кількість ітерацій атрактора Лоренца. Default: 250 (250e18).
    function lorenzIterations() external view returns (uint256) {
        return _parameters[KEY_LORENZ_ITERATIONS];
    }

    /// @notice Мінімальне Z-значення (CRITICAL_Z_MIN). Default: 2.0 (2e18).
    function lorenzZMin() external view returns (uint256) {
        return _parameters[KEY_LORENZ_Z_MIN];
    }

    /// @notice Максимальне Z-значення (CRITICAL_Z_MAX). Default: 45.0 (45e18).
    function lorenzZMax() external view returns (uint256) {
        return _parameters[KEY_LORENZ_Z_MAX];
    }

    /// @notice Оптимальне Z-значення (OPTIMAL_Z_TARGET). Default: 29.0 (29e18).
    function lorenzZTarget() external view returns (uint256) {
        return _parameters[KEY_LORENZ_Z_TARGET];
    }

    /// @notice Поріг страхового пулу для Dynamic Tax. Default: 100000 (100000e18).
    function insurancePoolThreshold() external view returns (uint256) {
        return _parameters[KEY_INSURANCE_POOL_THRESHOLD];
    }

    /// @notice Кількість SCC еквівалентних 1 тонні поглиненого CO₂ (D-MRV еквівалент).
    ///         Default: 2000 (2000e18). Визначає вагу кожного SCC у вуглецевих реєстрах.
    ///         1 SCC = 1/2000 tCO₂ = 0.5 kg CO₂.
    ///         Використовується: KlimaDAO retirement, Puro.earth CORC, ESG звітність.
    /// @dev [BIZ.1] CO₂ equivalence — закриває юридичний блокер для carbon registry integration.
    function sccPerTonneCo2() external view returns (uint256) {
        return _parameters[KEY_SCC_PER_TONNE_CO2];
    }

    /// @notice Поріг критичного стресу дерева для slash-тригера. Default: 0.83 (0.83e18).
    /// @dev [GOV.1] Це RF-confidence поріг `AiInsight.slash_stress_threshold` (бекенд-default
    ///      0.83); страховий поріг 0.8 — ОКРЕМИЙ концепт (05_05 §4), не цей ключ. Попередній
    ///      NatSpec «Default: 0.30» описував неіснуючий концепт — сет за ним упустив би
    ///      slash-тригер з 0.83 до 0.30 і залив би Field-Audit шумом.
    function stressThreshold() external view returns (uint256) {
        return _parameters[KEY_STRESS_THRESHOLD];
    }

    /// @notice [GOV.1] Показник γ опуклої slash-кривої (05_05 §3). Default: 1.3 (1.3e18).
    function slashGamma() external view returns (uint256) {
        return _parameters[KEY_SLASH_GAMMA];
    }

    /// @notice [GOV.1] Стеля penalty-МНОЖНИКА slash-кривої (не фінального ratio). Default: 2.0 (2e18).
    function slashPenaltyFactorMax() external view returns (uint256) {
        return _parameters[KEY_SLASH_PENALTY_FACTOR_MAX];
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
