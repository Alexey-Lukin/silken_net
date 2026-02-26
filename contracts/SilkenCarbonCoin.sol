// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Імпортуємо перевірені часом стандарти від OpenZeppelin
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Silken Carbon Coin (SCC)
 * @dev ERC20 Токен для D-MRV системи Silken Net.
 * Мінтити та конфісковувати токени може ТІЛЬКИ авторизований Оракул (наш Rails сервер).
 */
contract SilkenCarbonCoin is ERC20, Ownable {

    // =========================================================================
    // ПОДІЇ (EVENTS) ДЛЯ ПУБЛІЧНОГО АУДИТУ
    // =========================================================================

    // Фіксує, яке саме дерево згенерувало конкретний об'єм вуглецю
    event CarbonMinted(address indexed investor, uint256 amount, string treeDid);

    // Фіксує факт застосування Slashing Protocol (знищення лісу)
    event TokenSlashed(address indexed investor, uint256 amount);

    /**
     * @dev Конструктор. Встановлює назву токена, символ та адресу Оракула.
     * @param initialOracle Адреса гаманця нашого Rails-сервера
     */
    constructor(address initialOracle)
        ERC20("Silken Carbon Coin", "SCC")
        Ownable(initialOracle) 
    {}

    // =========================================================================
    // ЛОГІКА ОРАКУЛА (Дії, доступні лише серверу)
    // =========================================================================

    /**
     * @dev Головна функція мінтингу.
     * Модифікатор `onlyOwner` гарантує, що викликати її може лише сервер.
     * @param to Адреса гаманця інвестора (Organization.crypto_public_address)
     * @param amount Кількість токенів (у wei)
     * @param treeDid Унікальний ідентифікатор дерева, що згенерувало бали
     */
    function mint(address to, uint256 amount, string calldata treeDid) public onlyOwner {
        // Випускаємо токени на адресу інвестора
        _mint(to, amount);

        // Випромінюємо подію для публічного D-MRV аудиту
        emit CarbonMinted(to, amount, treeDid);
    }

    /**
     * @dev Функція карального спалювання (Slashing Protocol).
     * Дозволяє Оракулу конфіскувати та знищити токени інвестора,
     * якщо ліс (NaasContract) був знищений або розірваний.
     * @param investor Адреса інвестора, чиї токени конфіскуються
     * @param amount Кількість токенів для знищення
     */
    function slash(address investor, uint256 amount) public onlyOwner {
        _burn(investor, amount);

        // Фіксуємо факт покарання в блокчейні назавжди
        emit TokenSlashed(investor, amount);
    }

    // =========================================================================
    // ПУБЛІЧНА ЛОГІКА (Дії, доступні інвесторам)
    // =========================================================================

    /**
     * @dev Функція для добровільного спалювання токенів (Carbon Offsetting).
     * Коли компанія хоче офіційно "погасити" свій вуглецевий слід за рік,
     * вона викликає цю функцію, назавжди виводячи токени з власного обігу.
     * Будь-хто може спалити СВОЇ ВЛАСНІ токени.
     * @param amount Кількість токенів для погашення
     */
    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }
}
