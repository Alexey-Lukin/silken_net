// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title SilkenTimelock
 * @notice TimelockController для SilkenNet governance pipeline.
 * @dev Всі governance-рішення (зміна параметрів протоколу, ролей) проходять через
 *      48-годинну затримку. Це дає час DAO учасникам виявити та відреагувати
 *      на потенційно шкідливі зміни перед їх виконанням.
 *
 *      Pipeline: SFC holders → SilkenGovernor → SilkenTimelock (48h) → ProtocolParameters
 *
 *      pause() на SCC/SFC НЕ проходить через Timelock — потрібна миттєва реакція при exploits.
 *
 * @custom:security-contact security@silkennet.com
 */
contract SilkenTimelock is TimelockController {
    /// @notice Мінімальна затримка Timelock: 48 годин.
    /// @dev Достатньо для виявлення шкідливих пропозицій та організації veto.
    ///      Занадто коротко → ризик пропустити атаку; занадто довго → повільна реакція DAO.
    uint256 public constant MIN_DELAY_HOURS = 48;

    /// @notice Конструктор SilkenTimelock.
    /// @param proposers Масив адрес з правом пропозиції (зазвичай: тільки SilkenGovernor).
    /// @param executors Масив адрес з правом виконання. address(0) = будь-хто може execute після delay.
    /// @param admin Адміністратор Timelock. Рекомендовано: address(0) для immutable governance,
    ///              або Gnosis Safe multisig для bootstrap period.
    constructor(address[] memory proposers, address[] memory executors, address admin)
        TimelockController(
            MIN_DELAY_HOURS * 1 hours, // minDelay = 48 hours
            proposers,
            executors,
            admin
        )
        // solhint-disable-next-line no-empty-blocks

    {}
}
