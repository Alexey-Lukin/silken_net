// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/**
 * @title Silken Forest Coin (SFC)
 * @dev Governance/Security Токен для екосистеми Silken Net.
 * Версія 2.0: Багаторівневий контроль доступу, підтримка DAO-голосувань 
 * та Аварійна зупинка (Circuit Breaker).
 */
contract SilkenForestCoin is ERC20, AccessControl, Pausable, ERC20Permit, ERC20Votes {

    // =========================================================================
    // РОЛІ СИСТЕМИ (ZERO-TRUST)
    // =========================================================================
    
    // Роль для нашого Rails-сервера (Оракул, що нараховує бали біорізноманіття)
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // =========================================================================
    // ПОДІЇ ДЛЯ ПУБЛІЧНОГО АУДИТУ
    // =========================================================================
    event ForestMinted(address indexed investor, uint256 amount, string clusterId);

    /**
     * @dev Конструктор.
     * @param admin Адреса холодного гаманця (управління контрактом та пауза)
     * @param oracle Адреса гарячого гаманця Rails-сервера (емісія токенів)
     */
    constructor(address admin, address oracle)
        ERC20("Silken Forest Coin", "SFC")
        ERC20Permit("Silken Forest Coin")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, oracle);
    }

    // =========================================================================
    // ЛОГІКА ОРАКУЛА (Емісія)
    // =========================================================================

    /**
     * @dev Емісія токенів Оракулом (Rails).
     * Модифікатор `whenNotPaused` гарантує, що при атаці на сервер нові токени не випускатимуться.
     */
    function mint(address to, uint256 amount, string calldata clusterId) public onlyRole(MINTER_ROLE) whenNotPaused {
        _mint(to, amount);
        emit ForestMinted(to, amount, clusterId);
    }

    // =========================================================================
    // АДМІНІСТРУВАННЯ ТА БЕЗПЕКА (Circuit Breaker)
    // =========================================================================

    /**
     * @dev Аварійна зупинка контракту. Зупиняє всі перекази та мінтинг.
     * Викликається холодним гаманцем.
     */
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Відновлення роботи контракту.
     */
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // =========================================================================
    // ПЕРЕВИЗНАЧЕННЯ ФУНКЦІЙ (Вимоги стандартів)
    // =========================================================================

    /**
     * @dev Хук переміщення токенів. 
     * Ми об'єднуємо вимоги `ERC20Votes` (знімки балансів) та `Pausable` (зупинка).
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
        whenNotPaused
    {
        super._update(from, to, value);
    }

    /**
     * @dev Перевизначення для підтримки безгазових транзакцій (EIP-712).
     */
    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
