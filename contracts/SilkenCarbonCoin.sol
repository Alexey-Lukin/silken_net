// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title Silken Carbon Coin (SCC)
 * @notice Реалізація суверенної емісії вуглецевих активів для Silken Net.
 * @dev ERC20Permit додано для підтримки gasless approvals (EIP-2612).
 *      Це дозволяє власникам SCC підписувати approve() оффлайн,
 *      а relayer/backend подає підпис on-chain без газу від власника.
 *      Необхідно для майбутньої інтеграції з DEX, P2P marketplace та Paymaster (ERC-4337).
 *      ERC20Permit includes block.chainid in the EIP-712 domain separator,
 *      so permit() signatures are only valid on the chain where they were signed.
 *      Cross-chain replay is prevented by OpenZeppelin's domain separator implementation.
 *
 * [B-01] MAX_SUPPLY = 1 000 000 000 SCC — верхня межа емісії.
 * [B-02] Розділено MINTER_ROLE та SLASHER_ROLE на окремі oracle-адреси.
 * [B-03] Конструктор валідує ненульові адреси.
 * [B-04] batchMint обмежено 100 елементами для gas safety.
 * [B-10] Events: string поля не indexed, додано bytes32 indexed хеші.
 * [B-13] ReentrancyGuard для превентивного захисту.
 * [B-15] String length validation: treeDid/clusterId <= 256 bytes (The Graph safety).
 * @custom:security-contact security@silkennet.com
 */
contract SilkenCarbonCoin is ERC20, AccessControl, Pausable, ReentrancyGuard, ERC20Permit {
    /// @notice Роль для карбування нових токенів (Proof of Growth oracle).
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Роль для спалювання токенів при slashing protocol (окремий oracle).
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    /// @notice [SEC.1] Роль аварійної паузи — ВІДОКРЕМЛЕНА від DEFAULT_ADMIN_ROLE.
    /// @dev Тримає Gnosis Safe (миттєва реакція на exploit, поза 48h Timelock).
    ///      DEFAULT_ADMIN_ROLE (видача ролей, у т.ч. MINTER) у production = Timelock →
    ///      катастрофічний `grantRole(MINTER_ROLE)` несе 48h-затримку; pause лишається швидким.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice [B-01] Максимальна емісія SCC: 1 мільярд токенів (18 decimals).
    /// @dev Once MAX_SUPPLY is reached, mint/batchMint revert with "SCC: cap exceeded".
    /// @dev [CONTRACT.1] Деривація: 10 000 GP = 1 SCC · 2 000 SCC = 1 tCO2 → 1B SCC ≈
    ///      500 000 tCO2 ≈ 20M дерево-років (≈50 SCC/дерево/рік) ≈ 2M дерев × 10 років.
    ///      Свідомо-скромна launch-стеля pilot-горизонту (immutable) — планетарний
    ///      масштаб = новий деплой / L2-емісія, НЕ підняття цієї константи.
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18;

    /// @notice [B-04] Максимальна кількість елементів у batchMint для gas safety.
    /// @dev Зменшено з 200 до 100 для гарантії gas safety з максимальними рядками (256 bytes).
    uint256 public constant MAX_BATCH_SIZE = 100;

    /// @notice [B-15] Максимальна довжина `treeDid` у байтах (The Graph indexing safety).
    uint256 public constant MAX_STRING_BYTES = 256;

    /// @dev Лічильник адміністраторів для запобігання видаленню останнього DEFAULT_ADMIN_ROLE.
    uint256 private _adminCount;

    /// @notice Емітується при мінтингу SCC для конкретного дерева.
    /// @param investor Адреса отримувача токенів.
    /// @param amount Кількість токенів (wei).
    /// @param treeDidHash Keccak256 хеш DID дерева (indexed для пошуку).
    /// @param treeDid Повний DID дерева у читабельному вигляді.
    /// @param archiveRoot [E.60] Merkle-корінь телеметрія-архів-батчу диспатчу
    ///        (mint-anchored witness; indexed — аудиторський topic-lookup за root).
    ///        bytes32(0) = «без witness-клейму» (windowless/fail-open мінт), НЕ «порожньо».
    ///        Root = свідок evidence-набору ДИСПАТЧУ (N:1), не 1:1 композиції мінта.
    event CarbonMinted(
        address indexed investor,
        uint256 amount,
        bytes32 indexed treeDidHash,
        string treeDid,
        bytes32 indexed archiveRoot
    );

    /// @notice Емітується при спалюванні токенів через slashing protocol.
    /// @param investor Адреса, з якої спалюються токени.
    /// @param amount Кількість спалених токенів (wei).
    /// @param contextHash [CONTRACT.1] Атрибуція події: bytes32(intent BlockchainTransaction.id)
    ///        бекенда (прямий DB-вказівник для subgraph/аудитора; bytes32(0) = manual
    ///        DAO/Timelock slash без бекенд-інтенту).
    event TokenSlashed(address indexed investor, uint256 amount, bytes32 contextHash);

    /// @notice [B-02][B-03][SEC.1] Конструктор з розділеними ролями.
    /// @param admin Адміністратор (DEFAULT_ADMIN_ROLE) — у production = `SilkenTimelock`
    ///        (48h governance-затримка на видачу будь-якої ролі, у т.ч. MINTER_ROLE).
    /// @param pauser [SEC.1] Власник PAUSER_ROLE — у production = Gnosis Safe
    ///        (миттєва аварійна пауза, БЕЗ Timelock-затримки).
    /// @param minterOracle Oracle-адреса для мінтингу (MINTER_ROLE).
    /// @param slasherOracle Oracle-адреса для slashing (SLASHER_ROLE).
    constructor(address admin, address pauser, address minterOracle, address slasherOracle)
        ERC20("Silken Carbon Coin", "SCC")
        ERC20Permit("Silken Carbon Coin")
    {
        require(admin != address(0), "SCC: zero admin");
        require(pauser != address(0), "SCC: zero pauser");
        require(minterOracle != address(0), "SCC: zero minter oracle");
        require(slasherOracle != address(0), "SCC: zero slasher oracle");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        // Emits: RoleGranted(DEFAULT_ADMIN_ROLE, admin, msg.sender)
        _grantRole(PAUSER_ROLE, pauser);
        // Emits: RoleGranted(PAUSER_ROLE, pauser, msg.sender)
        _grantRole(MINTER_ROLE, minterOracle);
        // Emits: RoleGranted(MINTER_ROLE, minterOracle, msg.sender)
        _grantRole(SLASHER_ROLE, slasherOracle);
        // Emits: RoleGranted(SLASHER_ROLE, slasherOracle, msg.sender)
    }

    /// @notice [B-12] Емісія токенів для конкретного дерева на основі Proof of Growth.
    /// @param to Адреса отримувача.
    /// @param amount Кількість токенів (wei).
    /// @param treeDid DID дерева-джерела.
    /// @param archiveRoot [E.60] Merkle-корінь архів-батчу (bytes32(0) = без witness-клейму).
    /// @dev Reverts if totalSupply() + amount > MAX_SUPPLY.
    function mintForTree(address to, uint256 amount, string calldata treeDid, bytes32 archiveRoot)
        external
        nonReentrant
        onlyRole(MINTER_ROLE)
    {
        _mintSCC(to, amount, treeDid, archiveRoot);
    }

    /// @notice Backward-compatible alias для mintForTree.
    /// @param to Адреса отримувача.
    /// @param amount Кількість токенів (wei).
    /// @param treeDid DID дерева-джерела.
    /// @param archiveRoot [E.60] Merkle-корінь архів-батчу (bytes32(0) = без witness-клейму).
    /// @dev Reverts if totalSupply() + amount > MAX_SUPPLY.
    function mint(address to, uint256 amount, string calldata treeDid, bytes32 archiveRoot)
        external
        nonReentrant
        onlyRole(MINTER_ROLE)
    {
        _mintSCC(to, amount, treeDid, archiveRoot);
    }

    /// @dev Внутрішня реалізація мінтингу, спільна для mint() та mintForTree().
    ///      Усуває дублювання коду — будь-які зміни валідації або логіки
    ///      застосовуються до обох entry points одночасно. archiveRoot СВІДОМО
    ///      без валідації: zero32 = легальний «мінт без witness-клейму» (E.60).
    function _mintSCC(address to, uint256 amount, string calldata treeDid, bytes32 archiveRoot) internal {
        require(to != address(0), "SCC: zero recipient");
        require(amount > 0, "SCC: zero amount");
        require(bytes(treeDid).length > 0, "SCC: empty treeDid");
        require(bytes(treeDid).length <= MAX_STRING_BYTES, "SCC: treeDid too long");
        require(totalSupply() + amount <= MAX_SUPPLY, "SCC: cap exceeded");
        _mint(to, amount);
        emit CarbonMinted(to, amount, keccak256(bytes(treeDid)), treeDid, archiveRoot);
    }

    /// @notice [B-04] Масовий мінтинг токенів для економії газу при обробці всього сектора.
    /// @param recipients Масив адрес отримувачів (max MAX_BATCH_SIZE = 100).
    /// @param amounts Масив сум для кожного отримувача.
    /// @param treeDids Масив DID дерев-джерел.
    /// @param archiveRoot [E.60] ОДИН Merkle-корінь на весь батч (batch-level witness;
    ///        Ruby-шар гарантує «один batchMint = один архів-батч» за конструкцією).
    function batchMint(
        address[] calldata recipients,
        uint256[] calldata amounts,
        string[] calldata treeDids,
        bytes32 archiveRoot
    ) external nonReentrant onlyRole(MINTER_ROLE) {
        uint256 length = recipients.length;
        require(length > 0, "SCC: empty batch");
        require(length == amounts.length && length == treeDids.length, "SCC: array length mismatch");
        require(length <= MAX_BATCH_SIZE, "SCC: batch too large");

        // Gas optimization: single SLOAD for totalSupply + pre-calculated total
        uint256 batchTotal = 0;
        for (uint256 i = 0; i < length; i++) {
            require(recipients[i] != address(0), "SCC: zero recipient");
            require(amounts[i] > 0, "SCC: zero amount");
            uint256 didLen = bytes(treeDids[i]).length;
            require(didLen > 0, "SCC: empty treeDid");
            require(didLen <= MAX_STRING_BYTES, "SCC: treeDid too long");
            batchTotal += amounts[i];
        }
        require(totalSupply() + batchTotal <= MAX_SUPPLY, "SCC: cap exceeded");

        for (uint256 i = 0; i < length; i++) {
            _mint(recipients[i], amounts[i]);
            emit CarbonMinted(recipients[i], amounts[i], keccak256(bytes(treeDids[i])), treeDids[i], archiveRoot);
        }
    }

    /// @notice Спалювання токенів через slashing protocol (>20% аномальних дерев у кластері).
    /// @param investor Адреса, з якої спалюються токени.
    /// @param amount Кількість токенів для спалювання (wei).
    /// @dev Reverts if investor balance < amount ("SCC: insufficient balance").
    function slash(address investor, uint256 amount) external nonReentrant onlyRole(SLASHER_ROLE) {
        require(investor != address(0), "SCC: zero investor");
        require(amount > 0, "SCC: zero amount");
        require(balanceOf(investor) >= amount, "SCC: insufficient balance");
        _burn(investor, amount);
        // Manual DAO/Timelock-шлях — без бекенд-інтенту, contextHash порожній.
        emit TokenSlashed(investor, amount, bytes32(0));
    }

    /// @notice [SLASH.2] Спалювання до maxAmount, клампнуте до фактичного балансу (anti-evasion).
    /// @dev Бекенд рахує burn з pre-tax БД-сум, а on-chain баланс менший (DynamicTax у treasury,
    ///      SCC вільно переказуваний) — строгий slash() тоді revert-ить, і переказ 1 wei
    ///      перед транзакцією Оракула скасовував би повний slash. Тут min(maxAmount, balanceOf)
    ///      обчислюється атомарно в одній транзакції — гонки «прочитали баланс → front-run
    ///      переказом» не існує; виведення коштів лише зменшує спалюване до залишку.
    /// @param investor Адреса, з якої спалюються токени.
    /// @param maxAmount Верхня межа спалення (wei) — запитана бекендом сума.
    /// @param contextHash [CONTRACT.1] Атрибуція: bytes32(intent BlockchainTransaction.id).
    /// @return slashed Фактично спалена сума (wei) — її ж несе event TokenSlashed.
    /// @dev Reverts if investor holds nothing ("SCC: nothing to slash") — повне виведення
    ///      коштів бекенд ескалює як evasion окремим (юридичним) треком.
    function slashUpTo(address investor, uint256 maxAmount, bytes32 contextHash)
        external
        nonReentrant
        onlyRole(SLASHER_ROLE)
        returns (uint256 slashed)
    {
        require(investor != address(0), "SCC: zero investor");
        require(maxAmount > 0, "SCC: zero amount");
        slashed = balanceOf(investor);
        if (slashed > maxAmount) {
            slashed = maxAmount;
        }
        require(slashed > 0, "SCC: nothing to slash");
        _burn(investor, slashed);
        emit TokenSlashed(investor, slashed, contextHash);
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
    /// @dev Slashing — це механізм безпеки екосистеми, який НЕ повинен блокуватись адміном.
    ///      Якщо адмін може блокувати slash через pause(), це створює governance attack vector:
    ///      компрометований або зловмисний адмін може захистити порушників від слешингу.
    /// @dev Reentrancy protection is provided by nonReentrant guards on mint(), slash(), and batchMint().
    /// @dev Do NOT add external calls or callbacks to this function without adding nonReentrant guard.
    /// @dev Note: nonReentrant cannot be added here directly — it would conflict with the outer
    ///      nonReentrant guard on mint/slash/batchMint (nested nonReentrant reverts).
    function _update(address from, address to, uint256 value) internal override {
        // Allow burn (slash) to bypass pause — to == address(0) means _burn() was called.
        // Minting (from == 0, to != 0) and transfers (from != 0, to != 0) are still blocked.
        if (paused() && to != address(0)) {
            revert EnforcedPause();
        }
        super._update(from, to, value);
    }

    /// @dev Захист від видалення останнього DEFAULT_ADMIN_ROLE.
    ///      Якщо єдиний admin викличе renounceRole() або revokeRole(),
    ///      контракт стане назавжди некерованим: неможливо pause, неможливо замінити
    ///      компрометований oracle. Цей override запобігає цьому.
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
            require(_adminCount > 1, "SCC: cannot remove last admin");
        }
        bool revoked = super._revokeRole(role, account);
        if (revoked && role == DEFAULT_ADMIN_ROLE) {
            _adminCount--;
        }
        return revoked;
    }
}
