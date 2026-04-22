// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";

/**
 * @title SilkenGovernor
 * @notice DAO Governor для Gaia 2.0 — управління параметрами протоколу через SFC голосування.
 * @dev Реалізує OpenZeppelin Governor з повним захистом від Flash Loan атак:
 *
 *      1. **Snapshot Voting** (GovernorVotes): `getPastVotes(account, blockNumber)` замість `balanceOf()`.
 *         Flash Loan отримується ПІСЛЯ snapshot → не має voting power.
 *      2. **Voting Delay** (GovernorSettings): 7200 блоків (~1 день на Polygon).
 *         Зловмисник мусить тримати токени протягом delay — Flash Loan неможливий.
 *      3. **Quorum** (GovernorVotesQuorumFraction): 4% від totalSupply().
 *         Запобігає атакам малими обсягами.
 *      4. **Timelock** (GovernorTimelockControl): 48h затримка через SilkenTimelock.
 *         Дає час для реакції та vetoing шкідливих пропозицій.
 *
 *      Pipeline: SFC holders → propose() → vote() → queue() → [48h] → execute()
 *                                                                ↓
 *                                                   ProtocolParameters.setParameter()
 *
 * [ARCH.4] Governance DAO — protocol constants via on-chain governance.
 * [E.35]   Flash Loan defense: getPastVotes + 48h Timelock + votingDelay.
 * [BIZ.4]  DAO Governance Process — SFC voting mechanism.
 *
 * @custom:security-contact security@silkennet.io
 */
contract SilkenGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    /// @notice Конструктор SilkenGovernor.
    /// @param _token SFC (SilkenForestCoin) — governance token з ERC20Votes.
    /// @param _timelock SilkenTimelock — TimelockController з 48h мінімальною затримкою.
    constructor(IVotes _token, TimelockController _timelock)
        Governor("Silken Governor")
        GovernorSettings(
            7200,    // votingDelay: ~1 день на Polygon (block time ~2s, ~7200 блоків/день)
            50400,   // votingPeriod: ~7 днів на Polygon (~7200 блоків/день × 7 днів)
            100e18   // proposalThreshold: 100 SFC для створення пропозиції
        )
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(4)  // 4% quorum від totalSupply для прийняття
        GovernorTimelockControl(_timelock)
    // solhint-disable-next-line no-empty-blocks
    {}

    // ─── Required Overrides (OZ Diamond Inheritance Resolution) ──────

    /// @dev Повертає затримку голосування (блоки між створенням та початком голосування).
    function votingDelay()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    /// @dev Повертає тривалість голосування (кількість блоків).
    function votingPeriod()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    /// @dev Повертає мінімальний баланс SFC для створення пропозиції.
    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    /// @dev Повертає поточний quorum (4% від totalSupply при заданому timepoint).
    function quorum(uint256 blockNumber)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    /// @dev Стан пропозиції з урахуванням Timelock.
    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    /// @dev Чи потрібна черга (queue) перед виконанням. true — через Timelock.
    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    /// @dev Внутрішній хук для оновлення стану пропозиції.
    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(Governor, GovernorTimelockControl)
        returns (uint48)
    {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @dev Внутрішній хук для виконання пропозиції через Timelock.
    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(Governor, GovernorTimelockControl)
    {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @dev Скасування операцій в Timelock.
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(Governor, GovernorTimelockControl)
        returns (uint256)
    {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /// @dev Адреса executor (Timelock контракт).
    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }
}
