// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/**
 * @title Silken Forest Coin (SFC)
 * @notice Токен управління та біорізноманіття.
 */
contract SilkenForestCoin is ERC20, AccessControl, Pausable, ERC20Permit, ERC20Votes {

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    event ForestMinted(address indexed investor, uint256 amount, string indexed clusterId);

    constructor(address admin, address oracle)
        ERC20("Silken Forest Coin", "SFC")
        ERC20Permit("Silken Forest Coin")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, oracle);
    }

    function mint(address to, uint256 amount, string calldata clusterId) 
        external 
        onlyRole(MINTER_ROLE) 
        whenNotPaused 
    {
        _mint(to, amount);
        emit ForestMinted(to, amount, clusterId);
    }

    /**
     * @notice Пакетна емісія токенів управління.
     */
    function batchMint(
        address[] calldata recipients,
        uint256[] calldata amounts,
        string[] calldata clusterIds
    ) external onlyRole(MINTER_ROLE) whenNotPaused {
        uint256 length = recipients.length;
        require(length == amounts.length && length == clusterIds.length, "SFC: Array lengths mismatch");

        for (uint256 i = 0; i < length; i++) {
            _mint(recipients[i], amounts[i]);
            emit ForestMinted(recipients[i], amounts[i], clusterIds[i]);
        }
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        if (paused()) {
            revert EnforcedPause();
        }
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
