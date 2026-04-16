// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title StateRootAnchor
 * @notice Щотижнева фіналізація стану Gaia 2.0 в Ethereum Mainnet (L1).
 * @dev Зберігає 32-байтний SHA-256 state_root — криптографічний commitment
 *      глобального стану SilkenNet (total_scc + chain_hash + timestamp).
 *
 *      Один раз на тиждень EthereumAnchorWorker → StateAnchorService викликає
 *      storeStateRoot(bytes32), записуючи незмінний proof of state в Ethereum L1.
 *
 *      Gas-ефективність: тільки 1 SSTORE (bytes32) на тиждень.
 *
 * [BLOCKER-1] Контракт створено для заміни захардкодженого ABI в Ruby-сервісі.
 */
contract StateRootAnchor is AccessControl {

    /// @notice Роль для запису state root (EthereumAnchorWorker oracle).
    bytes32 public constant ANCHOR_ROLE = keccak256("ANCHOR_ROLE");

    /// @notice Останній збережений state root.
    bytes32 public latestRoot;

    /// @notice Timestamp останнього запису.
    uint256 public latestTimestamp;

    /// @notice Загальна кількість збережених state roots.
    uint256 public anchorCount;

    /// @notice Маппінг: state_root → block.timestamp коли він був збережений.
    mapping(bytes32 => uint256) public rootTimestamps;

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
    /// @param root 32-байтний SHA-256 дайджест глобального стану SilkenNet.
    function storeStateRoot(bytes32 root) external onlyRole(ANCHOR_ROLE) {
        require(root != bytes32(0), "StateRootAnchor: empty root");
        require(rootTimestamps[root] == 0, "StateRootAnchor: root already anchored");

        anchorCount++;
        latestRoot = root;
        latestTimestamp = block.timestamp;
        rootTimestamps[root] = block.timestamp;

        emit StateRootStored(root, block.timestamp, anchorCount);
    }

    /// @notice Перевірка, чи був конкретний state root коли-небудь збережений.
    /// @param root State root для перевірки.
    /// @return true якщо root був збережений.
    function isRootAnchored(bytes32 root) external view returns (bool) {
        return rootTimestamps[root] != 0;
    }
}
