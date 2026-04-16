// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
 * [B-04] batchMint обмежено 200 елементами для gas safety.
 * [B-10] Events: string поля не indexed, додано bytes32 indexed хеші.
 * [B-13] ReentrancyGuard для превентивного захисту.
 */
contract SilkenCarbonCoin is ERC20, AccessControl, Pausable, ReentrancyGuard, ERC20Permit {

    /// @notice Роль для карбування нових токенів (Proof of Growth oracle).
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Роль для спалювання токенів при slashing protocol (окремий oracle).
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    /// @notice [B-01] Максимальна емісія SCC: 1 мільярд токенів (18 decimals).
    /// @dev Once MAX_SUPPLY is reached, mint/batchMint revert with "SCC: cap exceeded".
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18;

    /// @notice [B-04] Максимальна кількість елементів у batchMint для gas safety.
    uint256 public constant MAX_BATCH_SIZE = 200;

    /// @notice Емітується при мінтингу SCC для конкретного дерева.
    /// @param investor Адреса отримувача токенів.
    /// @param amount Кількість токенів (wei).
    /// @param treeDidHash Keccak256 хеш DID дерева (indexed для пошуку).
    /// @param treeDid Повний DID дерева у читабельному вигляді.
    event CarbonMinted(address indexed investor, uint256 amount, bytes32 indexed treeDidHash, string treeDid);

    /// @notice Емітується при спалюванні токенів через slashing protocol.
    /// @param investor Адреса, з якої спалюються токени.
    /// @param amount Кількість спалених токенів (wei).
    event TokenSlashed(address indexed investor, uint256 amount);

    /// @notice Емітується при оплаті страхової премії (Parametric Insurance).
    /// @param payer Адреса платника премії.
    /// @param amount Сума премії (wei).
    event PremiumPaid(address indexed payer, uint256 amount);

    /// @notice [B-02][B-03] Конструктор з розділеними oracle-адресами.
    /// @param admin Адміністратор контракту (DEFAULT_ADMIN_ROLE).
    /// @param minterOracle Oracle-адреса для мінтингу (MINTER_ROLE).
    /// @param slasherOracle Oracle-адреса для slashing (SLASHER_ROLE).
    constructor(address admin, address minterOracle, address slasherOracle)
        ERC20("Silken Carbon Coin", "SCC")
        ERC20Permit("Silken Carbon Coin")
    {
        require(admin != address(0), "SCC: zero admin");
        require(minterOracle != address(0), "SCC: zero minter oracle");
        require(slasherOracle != address(0), "SCC: zero slasher oracle");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        // Emits: RoleGranted(DEFAULT_ADMIN_ROLE, admin, msg.sender)
        _grantRole(MINTER_ROLE, minterOracle);
        // Emits: RoleGranted(MINTER_ROLE, minterOracle, msg.sender)
        _grantRole(SLASHER_ROLE, slasherOracle);
        // Emits: RoleGranted(SLASHER_ROLE, slasherOracle, msg.sender)
    }

    /// @notice [B-12] Емісія токенів для конкретного дерева на основі Proof of Growth.
    /// @param to Адреса отримувача.
    /// @param amount Кількість токенів (wei).
    /// @param treeDid DID дерева-джерела.
    /// @dev Reverts if totalSupply() + amount > MAX_SUPPLY.
    function mintForTree(address to, uint256 amount, string calldata treeDid)
        external
        onlyRole(MINTER_ROLE)
        nonReentrant
    {
        require(to != address(0), "SCC: zero recipient");
        require(amount > 0, "SCC: zero amount");
        require(bytes(treeDid).length > 0, "SCC: empty treeDid");
        require(totalSupply() + amount <= MAX_SUPPLY, "SCC: cap exceeded");
        _mint(to, amount);
        emit CarbonMinted(to, amount, keccak256(bytes(treeDid)), treeDid);
    }

    /// @notice Backward-compatible alias для mintForTree.
    /// @param to Адреса отримувача.
    /// @param amount Кількість токенів (wei).
    /// @param treeDid DID дерева-джерела.
    /// @dev Reverts if totalSupply() + amount > MAX_SUPPLY.
    function mint(address to, uint256 amount, string calldata treeDid)
        external
        onlyRole(MINTER_ROLE)
        nonReentrant
    {
        require(to != address(0), "SCC: zero recipient");
        require(amount > 0, "SCC: zero amount");
        require(bytes(treeDid).length > 0, "SCC: empty treeDid");
        require(totalSupply() + amount <= MAX_SUPPLY, "SCC: cap exceeded");
        _mint(to, amount);
        emit CarbonMinted(to, amount, keccak256(bytes(treeDid)), treeDid);
    }

    /// @notice [B-04] Масовий мінтинг токенів для економії газу при обробці всього сектора.
    /// @param recipients Масив адрес отримувачів (max 200).
    /// @param amounts Масив сум для кожного отримувача.
    /// @param treeDids Масив DID дерев-джерел.
    function batchMint(
        address[] calldata recipients,
        uint256[] calldata amounts,
        string[] calldata treeDids
    ) external onlyRole(MINTER_ROLE) nonReentrant {
        uint256 length = recipients.length;
        require(length > 0, "SCC: empty batch");
        require(length == amounts.length && length == treeDids.length, "SCC: array length mismatch");
        require(length <= MAX_BATCH_SIZE, "SCC: batch too large");

        // Gas optimization: single SLOAD for totalSupply + pre-calculated total
        uint256 batchTotal = 0;
        for (uint256 i = 0; i < length; i++) {
            require(recipients[i] != address(0), "SCC: zero recipient");
            require(amounts[i] > 0, "SCC: zero amount");
            batchTotal += amounts[i];
        }
        require(totalSupply() + batchTotal <= MAX_SUPPLY, "SCC: cap exceeded");

        for (uint256 i = 0; i < length; i++) {
            _mint(recipients[i], amounts[i]);
            emit CarbonMinted(recipients[i], amounts[i], keccak256(bytes(treeDids[i])), treeDids[i]);
        }
    }

    /// @notice Спалювання токенів через slashing protocol (>20% аномальних дерев у кластері).
    /// @param investor Адреса, з якої спалюються токени.
    /// @param amount Кількість токенів для спалювання (wei).
    /// @dev Reverts if investor balance < amount ("SCC: insufficient balance").
    function slash(address investor, uint256 amount)
        external
        onlyRole(SLASHER_ROLE)
        nonReentrant
    {
        require(investor != address(0), "SCC: zero investor");
        require(amount > 0, "SCC: zero amount");
        require(balanceOf(investor) >= amount, "SCC: insufficient balance");
        _burn(investor, amount);
        emit TokenSlashed(investor, amount);
    }

    /// @notice Запис оплати страхової премії (Parametric Insurance).
    /// @param payer Адреса платника премії.
    /// @param amount Сума премії (wei).
    function recordPremiumPaid(address payer, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit PremiumPaid(payer, amount);
    }

    /// @notice Призупинення всіх трансферів (emergency).
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Відновлення трансферів після призупинення.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @dev [B-07] Уніфіковано: whenNotPaused modifier для всіх трансферів.
    /// @dev Reentrancy protection is provided by nonReentrant guards on mint(), slash(), and batchMint().
    /// @dev Do NOT add external calls or callbacks to this function without adding nonReentrant guard.
    /// @dev Note: nonReentrant cannot be added here directly — it would conflict with the outer
    ///      nonReentrant guard on mint/slash/batchMint (nested nonReentrant reverts).
    function _update(address from, address to, uint256 value)
        internal
        override
        whenNotPaused
    {
        super._update(from, to, value);
    }

    /// @notice Override nonces для сумісності ERC20Permit + Nonces.
    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
