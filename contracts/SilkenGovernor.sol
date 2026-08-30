// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";

/// @notice Мінімальна вʼюха на governance-токен — ЛИШЕ його стеля емісії.
/// @dev Свідомо НЕ імпортуємо `SilkenForestCoin` цілком: Governor приймає будь-який
///      `IVotes`-токен зі стелею, і жорсткий тип заборонив би SFC v2 без редеплою
///      Governor'а. One-Home числа при цьому збережено — стеля лишається у ТОКЕНА,
///      сюди вона потрапляє читанням, а не копією літерала.
interface ICappedVotesToken {
    // Ім'я НЕ наш вибір: це auto-getter публічної константи `MAX_SUPPLY` токена, тож
    // мусить збігатися з його ABI байт-у-байт. mixedCase зробив би виклик недійсним.
    // slither-disable-next-line naming-convention
    function MAX_SUPPLY() external view returns (uint256);
}

/**
 * @title SilkenGovernor
 * @notice DAO Governor для SilkenNet — управління параметрами протоколу через SFC голосування.
 * @dev Реалізує OpenZeppelin Governor з повним захистом від Flash Loan атак:
 *
 *      1. **Snapshot Voting** (GovernorVotes): `getPastVotes(account, blockNumber)` замість `balanceOf()`.
 *         Flash Loan отримується ПІСЛЯ snapshot → не має voting power.
 *      2. **Voting Delay** (GovernorSettings): 43200 блоків (~1 день на Polygon, block time ~2s).
 *         Зловмисник мусить тримати токени протягом delay — Flash Loan неможливий.
 *      3. **Quorum** (GovernorVotesQuorumFraction із перевизначеною БАЗОЮ): 4% від SFC
 *         `MAX_SUPPLY` = 4 000 000 SFC — фіксовано, НЕ від `getPastTotalSupply`.
 *         Запобігає і атакам малими обсягами, і захопленню на старті (↓ [DOC-T.89]).
 *      4. **Timelock** (GovernorTimelockControl): 48h затримка через SilkenTimelock.
 *         Дає час для реакції та vetoing шкідливих пропозицій.
 *
 *      Pipeline: SFC holders → propose() → vote() → queue() → [48h] → execute()
 *                                                                ↓
 *                                                   ProtocolParameters.setParameter()
 *
 *      ─── [DOC-T.89] Чому база quorum — СТЕЛЯ, а не обіг (присуд founder, 2026-08-26) ───
 *
 *      Genesis-supply нульовий: `Deploy.s.sol` не мінтить нічого, конструктори обох токенів
 *      роблять лише `_grantRole`. При базі `getPastTotalSupply` це означає, що ПЕРШИЙ
 *      отримувач емісії володіє DAO цілком — 4% від власного балансу він перекриває сам,
 *      а SFC ще й авто-делегує голос при мінті, тож жодної дії з його боку не потрібно.
 *
 *      Вийти з цього зсередини НЕМОЖЛИВО: обидва важелі — `updateQuorumNumerator` і
 *      `setProposalThreshold` — `onlyGovernance`, тобто міняються лише успішною пропозицією,
 *      а проксі в `contracts/` немає ЖОДНОГО. Зламаний старт незворотний.
 *
 *      Тому база = стеля емісії. Незворотна шкода тут — ЗАХОПЛЕННЯ, а не сон: DAO, що спить
 *      до реальної дистрибуції, — це відкладена подія (активація DAO і так окрема віха,
 *      [SEC.1]); DAO, захоплений на першому мінті, — це втрачений протокол.
 *
 *      ⚠️ Залишок, названий вголос: `quorumDenominator()` лишається 100, тож чисельник 100
 *      тепер означає 100% СТЕЛІ, а не 100% обігу. Зміст важеля змінився разом із базою —
 *      це свідомо, і голосування за чисельник має читати його саме так.
 *
 *      🔴 `proposalThreshold` лишається АБСОЛЮТНИМ `10_000e18` — НЕ робити його часткою і НЕ
 *      опускати в 0. Виміряно: `10_000e18` УЖЕ Є 0.01% від `MAX_SUPPLY`, тобто «зробити
 *      часткою» відтворює те саме число; а власний override зробив би `setProposalThreshold`
 *      ІНЕРТНИМ — governance-голос, який виглядає успішним і не змінює нічого. При quorum
 *      4 000 000 SFC поріг подання вже не є вектором захоплення: ПОДАТИ зможе багато хто,
 *      ПРИЙНЯТИ — лише реальна дистрибуція.
 *
 * [ARCH.4] Governance DAO — protocol constants via on-chain governance.
 * [E.35]   Flash Loan defense: getPastVotes + 48h Timelock + votingDelay.
 * [BIZ.4]  DAO Governance Process — SFC voting mechanism.
 *
 * @custom:security-contact security@silkennet.com
 */
contract SilkenGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    // ─── Polygon PoS Block Time Constants ─────────────────────────────
    // Polygon PoS average block time ≈ 2 seconds.
    // 1 day  = 86400s / 2s ≈ 43200 blocks
    // 7 days = 604800s / 2s ≈ 302400 blocks
    //
    // УВАГА: block time на Polygon може варіюватись (1.5–3s).
    // Ці значення є приблизними для governance UX, не для фінансових розрахунків.

    /// @notice [DOC-T.89] База розрахунку quorum — стеля емісії governance-токена (SFC `MAX_SUPPLY`).
    /// @dev Читається з токена ОДИН раз, у конструкторі: число лишається у власності токена
    ///      (One-Home), а `quorum()` не платить зовнішнім CALL за кожен виклик. Immutable —
    ///      отже після деплою база незмінна навіть для governance; тюниться лише чисельник.
    // UPPER_CASE свідомо: це ЄДИНИЙ immutable у всьому наборі контрактів, а всі сусідні
    // символи тієї ж ролі — `MAX_SUPPLY`, `MAX_BATCH_SIZE`, `*_ROLE` — константи в
    // UPPER_CASE. mixedCase зробив би його білою вороною серед власних однолітків заради
    // дефолту лінтера; до того ж це `public`, тож ім'я вже є частиною ABI.
    // slither-disable-next-line naming-convention
    uint256 public immutable QUORUM_BASE;

    /// @notice Конструктор SilkenGovernor.
    /// @param _token SFC (SilkenForestCoin) — governance token з ERC20Votes + стелею `MAX_SUPPLY`.
    /// @param _timelock SilkenTimelock — TimelockController з 48h мінімальною затримкою.
    constructor(IVotes _token, TimelockController _timelock)
        Governor("Silken Governor")
        GovernorSettings(
            43200, // votingDelay: ~1 день на Polygon (86400s / 2s per block)
            302400, // votingPeriod: ~7 днів на Polygon (604800s / 2s per block)
            // [CONTRACT.1] proposalThreshold: 10 000 SFC (0.01% MAX_SUPPLY) — anti-spam
            // (було 100 SFC = 0.0001%, spam-griefing вектор); founder-рішення 2026-07-04.
            // [DOC-T.89] Лишається АБСОЛЮТНИМ свідомо: 10_000e18 і Є 0.01% стелі, а override
            // зробив би setProposalThreshold інертним. Змінюється DAO-голосом (GovernorSettings).
            10_000e18
        )
        GovernorVotes(_token)
        // [DOC-T.89] 4% — ЧИСЕЛЬНИК; база = QUORUM_BASE (стеля SFC), не totalSupply. Батька
        // лишено навмисно: чисельник і далі живий onlyGovernance-важіль із власною історією.
        GovernorVotesQuorumFraction(4)
        GovernorTimelockControl(_timelock)
    {
        // Fail-closed на межі довіри: база 0 зробила б quorum нульовим, тобто будь-яка
        // пропозиція проходила б з одним голосом — рівно та шкода, яку цей фікс закриває.
        //
        // ⚠️ Форма «присвоїти РЕЗУЛЬТАТОМ виклику, потім перевірити» — навмисна, і
        // причина статична: попередня форма (`uint256 cap = …; require; QUORUM_BASE = cap;`)
        // давала Aderyn HIGH `reentrancy-state-change` — запис стану ПІСЛЯ зовнішнього
        // виклику. По суті це хибний позитив (конструктор: код Governor'а ще не встановлено,
        // тож реентрувати нікуди), але детектор конструкторів не розрізняє, а глушити
        // HIGH-детектор реентрансі заради одного сайту — гірша ціна, ніж переставити два
        // рядки. Семантика тотожна: revert відкочує все, тож нульова база недосяжна.
        // Читання immutable у конструкторі після присвоєння легальне з solc 0.8.8.
        QUORUM_BASE = ICappedVotesToken(address(_token)).MAX_SUPPLY();
        require(QUORUM_BASE > 0, "Governor: zero quorum base");
    }

    // ─── Required Overrides (OZ Diamond Inheritance Resolution) ──────

    /// @dev Повертає затримку голосування (блоки між створенням та початком голосування).
    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    /// @dev Повертає тривалість голосування (кількість блоків).
    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    /// @dev Повертає мінімальний баланс SFC для створення пропозиції.
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    /// @dev [DOC-T.89] Quorum = `quorumNumerator(timepoint)`/`quorumDenominator()` від
    ///      `QUORUM_BASE` (стеля SFC) — сьогодні 4% × 100 000 000 = 4 000 000 SFC, і це число
    ///      НЕ залежить від обігу. Дзеркалить `GovernorVotesQuorumFraction.quorum`, підмінивши
    ///      ЛИШЕ базу: чисельник читається з тієї самої checkpoint-історії, тож він і далі
    ///      живий `onlyGovernance`-важіль, а `quorumNumerator()` лишається арифметично правдивим.
    function quorum(uint256 blockNumber) public view override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
        return (QUORUM_BASE * quorumNumerator(blockNumber)) / quorumDenominator();
    }

    /// @dev Стан пропозиції з урахуванням Timelock.
    function state(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
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
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @dev Внутрішній хук для виконання пропозиції через Timelock.
    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @dev Скасування операцій в Timelock.
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /// @dev Адреса executor (Timelock контракт).
    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
