// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Silken Carbon Coin (SCC)
 * @notice Реалізація суверенної емісії вуглецевих активів для Silken Net.
 */
contract SilkenCarbonCoin is ERC20, AccessControl, Pausable {

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    // Індексуємо investor та treeDid для миттєвого пошуку в Subgraph або Rails
    event CarbonMinted(address indexed investor, uint256 amount, string indexed treeDid);
    event TokenSlashed(address indexed investor, uint256 amount);

    constructor(address admin, address oracle) ERC20("Silken Carbon Coin", "SCC") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin); 
        _grantRole(MINTER_ROLE, oracle);
        _grantRole(SLASHER_ROLE, oracle);
    }

    /**
     * @notice Емісія токенів на основі підтвердженого гомеостазу.
     * @param treeDid DID Солдата, який згенерував енергію.
     */
    function mint(address to, uint256 amount, string calldata treeDid) 
        external 
        onlyRole(MINTER_ROLE) 
    {
        _mint(to, amount);
        emit CarbonMinted(to, amount, treeDid);
    }

    /**
     * @notice Примусове вилучення токенів у разі деградації кластера (Slashing).
     * @dev Використовує внутрішній _burn, ігноруючи потребу в allowance, 
     * згідно з умовами NaaS-контракту.
     */
    function slash(address investor, uint256 amount) 
        external 
        onlyRole(SLASHER_ROLE) 
    {
        _burn(investor, amount);
        emit TokenSlashed(investor, amount);
    }

    // --- Аварійні протоколи ---

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // --- ERC20 Hooks ---

    function _update(address from, address to, uint256 value)
        internal
        override
        whenNotPaused
    {
        super._update(from, to, value);
    }
}
