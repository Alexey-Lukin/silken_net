// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title Silken Forest Coin (SFC)
 * @notice Токен управління (governance) та біорізноманіття для екосистеми SilkenNet.
 * @dev ERC20Votes додано для підтримки DAO governance (Governor/Timelock).
 *      ERC20Permit — gasless approvals (EIP-2612).
 *      ERC20Permit includes block.chainid in the EIP-712 domain separator,
 *      so permit() signatures are only valid on the chain where they were signed.
 *      Cross-chain replay is prevented by OpenZeppelin's domain separator implementation.
 *
 * [B-01] MAX_SUPPLY = 100 000 000 SFC — верхня межа емісії governance токенів.
 * [B-03] Конструктор валідує ненульові адреси.
 * [B-04] batchMint обмежено 100 елементами для gas safety.
 * [B-06] Додано SLASHER_ROLE та slash() для governance slashing.
 * [B-07] Уніфіковано: whenNotPaused modifier замість ручної перевірки.
 * [B-10] Events: string поля не indexed, додано bytes32 indexed хеші.
 * [B-13] ReentrancyGuard для превентивного захисту.
 * [B-14] Повний NatSpec для аудиту (CertiK/Hacken).
 * [B-15] String length validation: clusterId <= 256 bytes (The Graph safety).
 * @custom:security-contact security@silkennet.com
 */
contract SilkenForestCoin is ERC20, AccessControl, Pausable, ReentrancyGuard, ERC20Permit, ERC20Votes {
    /// @notice Роль для карбування нових governance токенів.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice [B-06] Роль для спалювання governance токенів при slashing protocol.
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    /// @notice [SEC.1] Роль аварійної паузи — ВІДОКРЕМЛЕНА від DEFAULT_ADMIN_ROLE.
    /// @dev Тримає Gnosis Safe (миттєва реакція на exploit, поза 48h Timelock).
    ///      DEFAULT_ADMIN_ROLE (видача ролей, у т.ч. MINTER) у production = Timelock →
    ///      катастрофічний `grantRole(MINTER_ROLE)` несе 48h-затримку; pause лишається швидким.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice [B-01] Максимальна емісія SFC: 100 мільйонів governance токенів (18 decimals).
    /// @dev Once MAX_SUPPLY is reached, mint/batchMint revert with "SFC: cap exceeded".
    uint256 public constant MAX_SUPPLY = 100_000_000 * 1e18;

    /// @notice [B-04] Максимальна кількість елементів у batchMint для gas safety.
    /// @dev Зменшено з 200 до 100 для гарантії gas safety з максимальними рядками (256 bytes).
    uint256 public constant MAX_BATCH_SIZE = 100;

    /// @notice [B-15] Максимальна довжина `clusterId` у байтах (The Graph indexing safety).
    uint256 public constant MAX_STRING_BYTES = 256;

    /// @dev Лічильник адміністраторів для запобігання видаленню останнього DEFAULT_ADMIN_ROLE.
    uint256 private _adminCount;

    /// @notice Емітується при мінтингу SFC для кластера.
    /// @param investor Адреса отримувача governance токенів.
    /// @param amount Кількість токенів (wei).
    /// @param clusterIdHash Keccak256 хеш ID кластера (indexed для пошуку).
    /// @param clusterId Повний ID кластера у читабельному вигляді.
    /// @param archiveRoot [E.60] Merkle-корінь телеметрія-архів-батчу диспатчу — MRV-witness
    ///        evidence-набору, НЕ carbon-клейм (токен-семантика живе в токені; SCC/SFC
    ///        симетричні за founder-рішенням — один Ruby ABI). bytes32(0) = без witness-клейму.
    event ForestMinted(
        address indexed investor,
        uint256 amount,
        bytes32 indexed clusterIdHash,
        string clusterId,
        bytes32 indexed archiveRoot
    );

    /// @notice [B-06] Емітується при спалюванні governance токенів через slashing protocol.
    /// @param investor Адреса, з якої спалюються governance токени.
    /// @param amount Кількість спалених токенів (wei).
    /// @param contextHash [CONTRACT.1] Атрибуція події: bytes32(intent BlockchainTransaction.id)
    ///        бекенда (прямий DB-вказівник для subgraph/аудитора; bytes32(0) = manual
    ///        DAO/Timelock slash без бекенд-інтенту).
    event GovernanceSlashed(address indexed investor, uint256 amount, bytes32 contextHash);

    /// @notice [B-03][SEC.1] Конструктор з розділеними ролями.
    /// @param admin Адміністратор (DEFAULT_ADMIN_ROLE) — у production = `SilkenTimelock`
    ///        (48h governance-затримка на видачу будь-якої ролі, у т.ч. MINTER_ROLE).
    /// @param pauser [SEC.1] Власник PAUSER_ROLE — у production = Gnosis Safe
    ///        (миттєва аварійна пауза, БЕЗ Timelock-затримки).
    /// @param oracle Oracle-адреса для мінтингу (MINTER_ROLE).
    /// @param slasherOracle Oracle-адреса для governance slashing (SLASHER_ROLE).
    constructor(address admin, address pauser, address oracle, address slasherOracle)
        ERC20("Silken Forest Coin", "SFC")
        ERC20Permit("Silken Forest Coin")
    {
        require(admin != address(0), "SFC: zero admin");
        require(pauser != address(0), "SFC: zero pauser");
        require(oracle != address(0), "SFC: zero oracle");
        require(slasherOracle != address(0), "SFC: zero slasher oracle");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        // Emits: RoleGranted(DEFAULT_ADMIN_ROLE, admin, msg.sender)
        _grantRole(PAUSER_ROLE, pauser);
        // Emits: RoleGranted(PAUSER_ROLE, pauser, msg.sender)
        _grantRole(MINTER_ROLE, oracle);
        // Emits: RoleGranted(MINTER_ROLE, oracle, msg.sender)
        _grantRole(SLASHER_ROLE, slasherOracle);
        // Emits: RoleGranted(SLASHER_ROLE, slasherOracle, msg.sender)
    }

    /// @notice Емісія governance токенів для кластера лісу.
    /// @param to Адреса отримувача.
    /// @param amount Кількість токенів (wei).
    /// @param clusterId ID кластера лісу.
    /// @param archiveRoot [E.60] Merkle-корінь архів-батчу (bytes32(0) = без witness-клейму).
    /// @dev Reverts if totalSupply() + amount > MAX_SUPPLY. archiveRoot СВІДОМО без валідації.
    function mint(address to, uint256 amount, string calldata clusterId, bytes32 archiveRoot)
        external
        nonReentrant
        onlyRole(MINTER_ROLE)
    {
        require(to != address(0), "SFC: zero recipient");
        require(amount > 0, "SFC: zero amount");
        require(bytes(clusterId).length > 0, "SFC: empty clusterId");
        require(bytes(clusterId).length <= MAX_STRING_BYTES, "SFC: clusterId too long");
        require(totalSupply() + amount <= MAX_SUPPLY, "SFC: cap exceeded");
        _mint(to, amount);
        // Auto-delegate to self if not yet delegated — ensures voting power is immediately active.
        // Without this, ERC20Votes requires explicit delegate() call, and most recipients
        // wouldn't know to delegate, leading to artificially low governance quorum.
        if (delegates(to) == address(0)) {
            _delegate(to, to);
        }
        emit ForestMinted(to, amount, keccak256(bytes(clusterId)), clusterId, archiveRoot);
    }

    /// @notice [B-04] Пакетна емісія governance токенів з обмеженням розміру масиву.
    /// @param recipients Масив адрес отримувачів (max MAX_BATCH_SIZE = 100).
    /// @param amounts Масив сум для кожного отримувача.
    /// @param clusterIds Масив ID кластерів.
    /// @param archiveRoot [E.60] ОДИН Merkle-корінь на весь батч (batch-level witness).
    function batchMint(
        address[] calldata recipients,
        uint256[] calldata amounts,
        string[] calldata clusterIds,
        bytes32 archiveRoot
    ) external nonReentrant onlyRole(MINTER_ROLE) {
        uint256 length = recipients.length;
        require(length > 0, "SFC: empty batch");
        require(length == amounts.length && length == clusterIds.length, "SFC: array length mismatch");
        require(length <= MAX_BATCH_SIZE, "SFC: batch too large");

        // Gas optimization: single SLOAD for totalSupply + pre-calculated total
        uint256 batchTotal = 0;
        for (uint256 i = 0; i < length; i++) {
            require(recipients[i] != address(0), "SFC: zero recipient");
            require(amounts[i] > 0, "SFC: zero amount");
            uint256 cidLen = bytes(clusterIds[i]).length;
            require(cidLen > 0, "SFC: empty clusterId");
            require(cidLen <= MAX_STRING_BYTES, "SFC: clusterId too long");
            batchTotal += amounts[i];
        }
        require(totalSupply() + batchTotal <= MAX_SUPPLY, "SFC: cap exceeded");

        for (uint256 i = 0; i < length; i++) {
            _mint(recipients[i], amounts[i]);
            // Auto-delegate to self if not yet delegated — same rationale as in mint().
            if (delegates(recipients[i]) == address(0)) {
                _delegate(recipients[i], recipients[i]);
            }
            emit ForestMinted(recipients[i], amounts[i], keccak256(bytes(clusterIds[i])), clusterIds[i], archiveRoot);
        }
    }

    /// @notice [B-06] Спалювання governance токенів через slashing protocol.
    /// @dev Видаляє DAO voting power у "нечесних" учасників після порушення NaaS контракту.
    /// @param investor Адреса, з якої спалюються governance токени.
    /// @param amount Кількість токенів для спалювання (wei).
    /// @dev Reverts if investor balance < amount ("SFC: insufficient balance").
    function slash(address investor, uint256 amount) external nonReentrant onlyRole(SLASHER_ROLE) {
        require(investor != address(0), "SFC: zero investor");
        require(amount > 0, "SFC: zero amount");
        require(balanceOf(investor) >= amount, "SFC: insufficient balance");
        _burn(investor, amount);
        // Manual DAO/Timelock-шлях — без бекенд-інтенту, contextHash порожній.
        emit GovernanceSlashed(investor, amount, bytes32(0));
    }

    /// @notice [SLASH.2] Спалювання до maxAmount, клампнуте до фактичного балансу (anti-evasion).
    /// @dev Дзеркало SCC.slashUpTo: строгий slash() revert-ить, коли учасник переказав хоч
    ///      1 wei до транзакції Оракула — voting power порушника тоді виживає повний slash.
    ///      min(maxAmount, balanceOf) обчислюється атомарно; виведення лише зменшує спалюване.
    /// @param investor Адреса, з якої спалюються governance токени.
    /// @param maxAmount Верхня межа спалення (wei) — запитана бекендом сума.
    /// @param contextHash [CONTRACT.1] Атрибуція: bytes32(intent BlockchainTransaction.id).
    /// @return slashed Фактично спалена сума (wei) — її ж несе event GovernanceSlashed.
    /// @dev Reverts if investor holds nothing ("SFC: nothing to slash").
    function slashUpTo(address investor, uint256 maxAmount, bytes32 contextHash)
        external
        nonReentrant
        onlyRole(SLASHER_ROLE)
        returns (uint256 slashed)
    {
        require(investor != address(0), "SFC: zero investor");
        require(maxAmount > 0, "SFC: zero amount");
        slashed = balanceOf(investor);
        if (slashed > maxAmount) {
            slashed = maxAmount;
        }
        require(slashed > 0, "SFC: nothing to slash");
        _burn(investor, slashed);
        emit GovernanceSlashed(investor, slashed, contextHash);
    }

    /// @notice [SEC.1] Призупинення всіх трансферів (emergency) — PAUSER_ROLE (Safe),
    ///         навмисно ШВИДКЕ (поза Timelock) для негайної реакції на exploit.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice [SEC.1] Відновлення трансферів після призупинення — PAUSER_ROLE.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @dev [B-07] Трансфери та мінтинг блокуються при паузі, але burn (slash) дозволено.
    /// @dev Slashing governance токенів — це механізм безпеки DAO, який НЕ повинен блокуватись адміном.
    ///      Видалення voting power у порушників має бути завжди можливим.
    /// @dev Reentrancy protection is provided by nonReentrant guards on mint(), slash(), and batchMint().
    /// @dev Do NOT add external calls or callbacks to this function without adding nonReentrant guard.
    /// @dev Note: nonReentrant cannot be added here directly — it would conflict with the outer
    ///      nonReentrant guard on mint/slash/batchMint (nested nonReentrant reverts).
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        // Allow burn (slash) to bypass pause — to == address(0) means _burn() was called.
        // Minting (from == 0, to != 0) and transfers (from != 0, to != 0) are still blocked.
        if (paused() && to != address(0)) {
            revert EnforcedPause();
        }
        super._update(from, to, value);
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
            require(_adminCount > 1, "SFC: cannot remove last admin");
        }
        bool revoked = super._revokeRole(role, account);
        if (revoked && role == DEFAULT_ADMIN_ROLE) {
            _adminCount--;
        }
        return revoked;
    }

    /// @notice Override nonces for ERC20Permit + ERC20Votes diamond inheritance resolution.
    /// @dev Both ERC20Permit and Votes (via ERC20Votes) inherit Nonces, creating a diamond
    ///      that requires explicit override in the derived contract.
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
