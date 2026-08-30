// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title StateRootAnchor
 * @notice Щотижнева фіналізація стану SilkenNet в Ethereum Mainnet (L1).
 * @dev Зберігає 32-байтний SHA-256 state_root — криптографічний commitment
 *      глобального стану SilkenNet. Склад leaf0 (SSOT формули — docs/05_04 §3):
 *      total_growth_points | total_sfc | active_tree_count | chain_hash |
 *      anchored_at | total_scc_supply.
 *      NB [ARCH.97]: перше поле — БАЛИ офчейн-леджера, останнє — чинний
 *      SCC-supply (Σmints−Σburns). Доти NatSpec описував 3-польову формулу
 *      (протух від E.53/E.54) і називав балову величину «total_scc», тобто
 *      монетою; контракт байтів не інтерпретує, але опис вводив в оману.
 *
 *      Один раз на тиждень EthereumAnchorWorker → StateAnchorService викликає
 *      storeStateRoot(bytes32), записуючи незмінний proof of state в Ethereum L1.
 *
 *      Gas-ефективність: тільки 1 SSTORE (bytes32) на тиждень.
 *
 * [BLOCKER-1] Контракт створено для заміни захардкодженого ABI в Ruby-сервісі.
 * @custom:security-contact security@silkennet.com
 */
contract StateRootAnchor is AccessControl {
    /// @notice Роль для запису state root (EthereumAnchorWorker oracle).
    bytes32 public constant ANCHOR_ROLE = keccak256("ANCHOR_ROLE");

    /// @notice Мінімальний інтервал між якоруваннями (6 днів = буфер для тижневого розкладу).
    /// @dev Запобігає спаму фейковими state roots компрометованим oracle.
    uint256 public constant MIN_ANCHOR_INTERVAL = 6 days;

    /// @notice Останній збережений state root.
    bytes32 public latestRoot;

    /// @notice Timestamp останнього запису.
    uint256 public latestTimestamp;

    /// @notice Загальна кількість збережених state roots.
    uint256 public anchorCount;

    /// @notice Timestamp останнього якорування (для перевірки мінімального інтервалу).
    uint256 public lastAnchorTime;

    /// @notice Маппінг: state_root → block.timestamp коли він був збережений.
    mapping(bytes32 => uint256) public rootTimestamps;

    /// @notice Маппінг: anchorIndex → state_root для ефективних історичних запитів.
    /// @dev Дозволяє аудиторам запитувати state root за порядковим номером без сканування
    ///      event logs. Необхідно для ISO 14064 / Verra VCS compliance.
    mapping(uint256 => bytes32) public rootHistory;

    /// @dev Лічильник адміністраторів для запобігання видаленню останнього DEFAULT_ADMIN_ROLE.
    uint256 private _adminCount;

    /// @notice Емітується при кожному записі state root.
    /// @param root 32-байтний SHA-256 state root.
    /// @param timestamp Block timestamp запису.
    /// @param anchorIndex Порядковий номер запису (починаючи з 1).
    event StateRootStored(bytes32 indexed root, uint256 timestamp, uint256 anchorIndex);

    /// @notice Конструктор з валідацією ненульових адрес.
    /// @param admin Адміністратор контракту (DEFAULT_ADMIN_ROLE).
    /// @param anchorOracle Oracle-адреса для запису state roots (ANCHOR_ROLE).
    constructor(address admin, address anchorOracle) {
        require(admin != address(0), "StateRootAnchor: zero admin");
        require(anchorOracle != address(0), "StateRootAnchor: zero oracle");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        // Emits: RoleGranted(DEFAULT_ADMIN_ROLE, admin, msg.sender)
        _grantRole(ANCHOR_ROLE, anchorOracle);
        // Emits: RoleGranted(ANCHOR_ROLE, anchorOracle, msg.sender)
    }

    /// @notice Запис нового state root в Ethereum L1.
    /// @dev Кожен state root може бути записаний тільки один раз (immutability).
    ///      Мінімальний інтервал між записами — 6 днів (захист від спаму).
    ///      block.timestamp може відрізнятись від реального часу подання до ~12 секунд
    ///      через Ethereum PoS validator timestamp flexibility. Для compliance-звітності
    ///      використовуйте off-chain EthereumAnchor.anchored_at як точний timestamp.
    /// @param root 32-байтний SHA-256 дайджест глобального стану SilkenNet.
    function storeStateRoot(bytes32 root) external onlyRole(ANCHOR_ROLE) {
        require(root != bytes32(0), "StateRootAnchor: empty root");
        require(rootTimestamps[root] == 0, "StateRootAnchor: root already anchored");
        require(block.timestamp >= lastAnchorTime + MIN_ANCHOR_INTERVAL, "StateRootAnchor: too soon since last anchor");

        lastAnchorTime = block.timestamp;
        anchorCount++;
        latestRoot = root;
        latestTimestamp = block.timestamp;
        rootTimestamps[root] = block.timestamp;
        rootHistory[anchorCount] = root;

        emit StateRootStored(root, block.timestamp, anchorCount);
    }

    /// @notice Перевірка, чи був конкретний state root коли-небудь збережений.
    /// @param root State root для перевірки.
    /// @return true якщо root був збережений.
    function isRootAnchored(bytes32 root) external view returns (bool) {
        return rootTimestamps[root] != 0;
    }

    /// @notice Отримання state root за порядковим номером (anchorIndex).
    /// @dev Дозволяє аудиторам запитувати історичні state roots без сканування event logs.
    /// @param index Порядковий номер запису (1-based, від 1 до anchorCount).
    /// @return root 32-байтний state root.
    /// @return timestamp Block timestamp коли root був збережений.
    function getRootAtIndex(uint256 index) external view returns (bytes32 root, uint256 timestamp) {
        require(index > 0 && index <= anchorCount, "StateRootAnchor: invalid index");
        root = rootHistory[index];
        timestamp = rootTimestamps[root];
    }

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
            require(_adminCount > 1, "StateRootAnchor: cannot remove last admin");
        }
        bool revoked = super._revokeRole(role, account);
        if (revoked && role == DEFAULT_ADMIN_ROLE) {
            _adminCount--;
        }
        return revoked;
    }
}
