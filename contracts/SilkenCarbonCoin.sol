// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title Silken Carbon Coin (SCC)
 * @notice Реалізація суверенної емісії вуглецевих активів для Silken Net.
 * @dev ERC20Permit додано для підтримки gasless approvals (EIP-2612).
 *      Це дозволяє власникам SCC підписувати approve() оффлайн,
 *      а relayer/backend подає підпис on-chain без газу від власника.
 *      Необхідно для майбутньої інтеграції з DEX, P2P marketplace та Paymaster (ERC-4337).
 */
contract SilkenCarbonCoin is ERC20, AccessControl, Pausable, ERC20Permit {

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    event CarbonMinted(address indexed investor, uint256 amount, string indexed treeDid);
    event TokenSlashed(address indexed investor, uint256 amount);

    constructor(address admin, address oracle)
        ERC20("Silken Carbon Coin", "SCC")
        ERC20Permit("Silken Carbon Coin")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin); 
        _grantRole(MINTER_ROLE, oracle);
        _grantRole(SLASHER_ROLE, oracle);
    }

    /**
     * @notice Емісія токенів на основі підтвердженого гомеостазу.
     */
    function mint(address to, uint256 amount, string calldata treeDid) 
        external 
        onlyRole(MINTER_ROLE) 
    {
        _mint(to, amount);
        emit CarbonMinted(to, amount, treeDid);
    }

    /**
     * @notice Масовий мінтинг токенів для економії газу при обробці всього сектора.
     * @param recipients Масив адрес отримувачів.
     * @param amounts Масив сум для кожного отримувача.
     * @param treeDids Масив DID дерев-джерел.
     */
    function batchMint(
        address[] calldata recipients,
        uint256[] calldata amounts,
        string[] calldata treeDids
    ) external onlyRole(MINTER_ROLE) {
        uint256 length = recipients.length;
        require(length == amounts.length && length == treeDids.length, "SCC: Array lengths mismatch");

        for (uint256 i = 0; i < length; i++) {
            _mint(recipients[i], amounts[i]);
            emit CarbonMinted(recipients[i], amounts[i], treeDids[i]);
        }
    }

    function slash(address investor, uint256 amount) 
        external 
        onlyRole(SLASHER_ROLE) 
    {
        _burn(investor, amount);
        emit TokenSlashed(investor, amount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _update(address from, address to, uint256 value)
        internal
        override
        whenNotPaused
    {
        super._update(from, to, value);
    }

    /**
     * @notice Override nonces для сумісності ERC20Permit + Nonces.
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
