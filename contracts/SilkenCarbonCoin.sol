// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Silken Carbon Coin (SCC)
 * @dev ERC20 Токен для D-MRV системи Silken Net.
 * Версія 2.0: Багаторівневий контроль доступу (AccessControl) та Аварійна зупинка (Pausable).
 */
contract SilkenCarbonCoin is ERC20, AccessControl, Pausable {

    // =========================================================================
    // РОЛІ СИСТЕМИ (ZERO-TRUST АРХІТЕКТУРА)
    // =========================================================================
    
    // Роль для нашого Rails-сервера (нарахування балів)
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    // Роль для арбітражу/D-MRV (каральне спалювання при вирубці/пожежі)
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    // =========================================================================
    // ПОДІЇ ДЛЯ ПУБЛІЧНОГО АУДИТУ
    // =========================================================================
    event CarbonMinted(address indexed investor, uint256 amount, string treeDid);
    event TokenSlashed(address indexed investor, uint256 amount);

    /**
     * @dev Конструктор.
     * @param admin Адреса холодного гаманця співзасновників (Ledger/Trezor)
     * @param oracle Адреса гаманця нашого Rails-сервера (гарячий гаманець)
     */
    constructor(address admin, address oracle) ERC20("Silken Carbon Coin", "SCC") {
        // DEFAULT_ADMIN_ROLE може призначати та забирати інші ролі
        _grantRole(DEFAULT_ADMIN_ROLE, admin); 
        
        // Надаємо Rails-серверу права на емісію та спалювання
        _grantRole(MINTER_ROLE, oracle);
        _grantRole(SLASHER_ROLE, oracle);
    }

    // =========================================================================
    // ЛОГІКА ОРАКУЛА (Дії, доступні лише серверу)
    // =========================================================================

    /**
     * @dev Головна функція мінтингу.
     * @param to Адреса гаманця інвестора
     * @param amount Кількість токенів (у wei)
     * @param treeDid Унікальний ідентифікатор дерева
     */
    function mint(address to, uint256 amount, string calldata treeDid) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
        emit CarbonMinted(to, amount, treeDid);
    }

    /**
     * @dev Функція карального спалювання (Slashing Protocol).
     * @param investor Адреса інвестора, чиї токени конфіскуються
     * @param amount Кількість токенів для знищення
     */
    function slash(address investor, uint256 amount) public onlyRole(SLASHER_ROLE) {
        _burn(investor, amount);
        emit TokenSlashed(investor, amount);
    }

    // =========================================================================
    // ПУБЛІЧНА ЛОГІКА ТА АДМІНІСТРУВАННЯ
    // =========================================================================

    /**
     * @dev Функція для добровільного спалювання токенів (Carbon Offsetting).
     */
    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }

    /**
     * @dev Аварійна зупинка контракту.
     * Викликається холодним гаманцем, якщо сервер Оракула був скомпрометований.
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
    // ПЕРЕВИЗНАЧЕННЯ ВНУТРІШНІХ ФУНКЦІЙ (ERC20 Hook)
    // =========================================================================

    /**
     * @dev Цей хук (hook) викликається перед БУДЬ-ЯКИМ переміщенням токенів 
     * (переказ, мінтинг, спалювання). 
     * Модифікатор `whenNotPaused` гарантує, що при паузі всі фінансові потоки завмирають.
     */
    function _update(address from, address to, uint256 value)
        internal
        override
        whenNotPaused
    {
        super._update(from, to, value);
    }
}
