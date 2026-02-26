// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/**
 * @title Silken Forest Coin (SFC)
 * @dev Governance/Security Токен для екосистеми Silken Net.
 * Видається за підтримання біорізноманіття та гомеостазу лісу.
 */
contract SilkenForestCoin is ERC20, Ownable, ERC20Permit, ERC20Votes {

    event ForestMinted(address indexed investor, uint256 amount, string clusterId);

    constructor(address initialOracle)
        ERC20("Silken Forest Coin", "SFC")
        Ownable(initialOracle) 
        ERC20Permit("Silken Forest Coin")
    {}

    /**
     * @dev Емісія токенів Оракулом (Rails).
     */
    function mint(address to, uint256 amount, string calldata clusterId) public onlyOwner {
        _mint(to, amount);
        emit ForestMinted(to, amount, clusterId);
    }

    // =========================================================================
    // ПЕРЕВИЗНАЧЕННЯ ФУНКЦІЙ (Вимога стандарту ERC20Votes)
    // =========================================================================

    // Ці функції необхідні для того, щоб блокчейн автоматично робив "знімки"
    // балансів для чесного голосування (щоб ніхто не міг перекинути токени
    // на інший гаманець і проголосувати двічі).

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
