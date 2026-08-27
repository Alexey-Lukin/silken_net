// SPDX-License-Identifier: AGPL-3.0-or-later
import { BigInt } from "@graphprotocol/graph-ts";
import {
  CarbonMinted,
  TokenSlashed,
} from "../generated/SilkenCarbonCoin/SilkenCarbonCoin";
import {
  ForestMinted,
  GovernanceSlashed,
} from "../generated/SilkenForestCoin/SilkenForestCoin";
import {
  ParameterUpdated,
} from "../generated/ProtocolParameters/ProtocolParameters";
import {
  CarbonMintEvent,
  ForestMintEvent,
  GovernanceSlashEvent,
  ParameterChangeEvent,
  ProtocolFinancials,
  SlashingEvent,
} from "../generated/schema";

// 🔴 [DOC-T.89, ⚖️ 2026-08-26] Природа емісії деривується з префікса `identifier`.
// Дім префіксів — Rails `BlockchainMintingService` (`INSURANCE_MINT_PREFIX`,
// `"TAX_BATCH_"` у `build_batch_arrays`); дзеркало типу — `enum MintKind` у
// schema.graphql. Розійдуться — класифікація поїде МОВЧКИ, тож грепай DOC-T.89 обабіч.
const INSURANCE_MINT_PREFIX = "INS_";
const TAX_BATCH_PREFIX = "TAX_BATCH_";

function mintKindOf(identifier: string): string {
  // Порядок НЕ довільний: податковий запис несе identifier ПЕРШОЇ tx підбатча, а вона
  // сама може бути страховою → `TAX_BATCH_INS_<did>`. Спершу зовнішній префікс.
  if (identifier.startsWith(TAX_BATCH_PREFIX)) return "TAX";
  if (identifier.startsWith(INSURANCE_MINT_PREFIX)) return "INSURANCE";
  // ⚠️ GROWTH = ВІДСУТНІСТЬ мітки, а не власна мітка (на дроті її немає). Отже будь-який
  // майбутній нерозпізнаний префікс упаде сюди — помилка класифікації завжди на користь
  // «це вуглецевий клейм». Саме тому розбіжність із Rails — money-path-баг, не косметика.
  return "GROWTH";
}

function subjectDidOf(identifier: string): string {
  let did = identifier;
  if (did.startsWith(TAX_BATCH_PREFIX)) did = did.slice(TAX_BATCH_PREFIX.length);
  if (did.startsWith(INSURANCE_MINT_PREFIX)) did = did.slice(INSURANCE_MINT_PREFIX.length);
  return did;
}

function getProtocolFinancials(): ProtocolFinancials {
  let financials = ProtocolFinancials.load("1");
  if (financials == null) {
    financials = new ProtocolFinancials("1");
    financials.totalMinted = BigInt.zero();
    financials.totalMintedGrowth = BigInt.zero();
    financials.totalMintedInsurance = BigInt.zero();
    financials.totalMintedTax = BigInt.zero();
    financials.totalBurned = BigInt.zero();
    financials.totalForestMinted = BigInt.zero();
    financials.totalGovernanceSlashed = BigInt.zero();
  }
  return financials;
}

export function handleCarbonMinted(event: CarbonMinted): void {
  let id =
    event.transaction.hash.toHexString() +
    "-" +
    event.logIndex.toString();
  let entity = new CarbonMintEvent(id);

  entity.to = event.params.investor;
  entity.amount = event.params.amount;
  entity.treeDidHash = event.params.treeDidHash;
  entity.treeDid = event.params.treeDid; // RAW, вербатим — префікс природи ВКЛЮЧЕНО
  let kind = mintKindOf(event.params.treeDid);
  entity.kind = kind;
  entity.subjectDid = subjectDidOf(event.params.treeDid);
  entity.archiveRoot = event.params.archiveRoot; // [E.60] dispatch archive-batch witness
  entity.timestamp = event.block.timestamp;
  entity.blockNumber = event.block.number;
  entity.transactionHash = event.transaction.hash;

  entity.save();

  let financials = getProtocolFinancials();
  // ⚖️ `totalMinted` лишається Σ УСІХ природ (supply-бік тотожності з `totalBurned`) —
  // рознесення додається ПОРУЧ, не замість. Інваріант, який тримає цей блок:
  // totalMinted == totalMintedGrowth + totalMintedInsurance + totalMintedTax.
  financials.totalMinted = financials.totalMinted.plus(event.params.amount);
  if (kind == "TAX") {
    financials.totalMintedTax = financials.totalMintedTax.plus(event.params.amount);
  } else if (kind == "INSURANCE") {
    financials.totalMintedInsurance = financials.totalMintedInsurance.plus(
      event.params.amount
    );
  } else {
    financials.totalMintedGrowth = financials.totalMintedGrowth.plus(
      event.params.amount
    );
  }
  financials.save();
}

export function handleTokenSlashed(event: TokenSlashed): void {
  let id =
    event.transaction.hash.toHexString() +
    "-" +
    event.logIndex.toString();
  let entity = new SlashingEvent(id);

  entity.target = event.params.investor;
  entity.amount = event.params.amount;
  entity.contextHash = event.params.contextHash; // [CONTRACT.1] DB-attribution
  entity.timestamp = event.block.timestamp;

  entity.save();

  let financials = getProtocolFinancials();
  financials.totalBurned = financials.totalBurned.plus(event.params.amount);
  financials.save();
}

// [S3.5] SFC: ForestMinted event handler — governance token minting per cluster
//
// ⚠️ [DOC-T.89] Рознесення природ тут СВІДОМО НЕМАЄ, і межа названа: `TAX_BATCH_` на
// SFC не буває взагалі (`taxing?` віддає false для всього, крім carbon_coin), а `INS_`
// теоретично можливий — `identifier_for` клеїть префікс незалежно від токена — але
// SFC-виплату жорстко відхиляє `InsurancePayoutWorker` до активації governance (SEC.1).
// Тобто `clusterId` тут сьогодні завжди чистий. 🔦 Знімаєш той гард — дзеркаль `kind`
// і на `ForestMintEvent`, інакше `totalForestMinted` успадкує рівно цей дефект.
export function handleForestMinted(event: ForestMinted): void {
  let id =
    event.transaction.hash.toHexString() +
    "-" +
    event.logIndex.toString();
  let entity = new ForestMintEvent(id);

  entity.to = event.params.investor;
  entity.amount = event.params.amount;
  entity.clusterIdHash = event.params.clusterIdHash;
  entity.clusterId = event.params.clusterId;
  entity.archiveRoot = event.params.archiveRoot; // [E.60] MRV-witness, not a carbon claim
  entity.timestamp = event.block.timestamp;
  entity.blockNumber = event.block.number;
  entity.transactionHash = event.transaction.hash;

  entity.save();

  let financials = getProtocolFinancials();
  financials.totalForestMinted = financials.totalForestMinted.plus(
    event.params.amount
  );
  financials.save();
}

// [S3.5] SFC: GovernanceSlashed event handler — DAO slashing of voting power
export function handleGovernanceSlashed(event: GovernanceSlashed): void {
  let id =
    event.transaction.hash.toHexString() +
    "-" +
    event.logIndex.toString();
  let entity = new GovernanceSlashEvent(id);

  entity.target = event.params.investor;
  entity.amount = event.params.amount;
  entity.contextHash = event.params.contextHash; // [CONTRACT.1] DB-attribution
  entity.timestamp = event.block.timestamp;
  entity.blockNumber = event.block.number;
  entity.transactionHash = event.transaction.hash;

  entity.save();

  let financials = getProtocolFinancials();
  financials.totalGovernanceSlashed =
    financials.totalGovernanceSlashed.plus(event.params.amount);
  financials.save();
}

// 🔭 [ARCH.111] ЗАКОН, за яким видали гроші.
//
// Це ЄДИНА governance-подія індексу, і вона тут не заради повноти: без історії
// ставки вже опубліковане `ProtocolFinancials.totalMintedTax` зовнішньо
// неперевірне — аудитор бачить зібраний податок і не може звірити його з чинною
// на той момент ставкою. Тобто арифметична передумова наявного числа.
//
// ⛔ Агрегату тут СВІДОМО немає: «остання ставка» була б новим твердженням
// системи про себе, тоді як предмет — сам ПОТІК змін, який читач згортає сам за
// потрібне вікно. Ролі/пауза/Timelock/Governor не індексуються — оголошена межа
// предмета в шапці `subgraph.yaml`.
export function handleParameterUpdated(event: ParameterUpdated): void {
  let id =
    event.transaction.hash.toHexString() +
    "-" +
    event.logIndex.toString();
  let entity = new ParameterChangeEvent(id);

  entity.key = event.params.key;
  entity.oldValue = event.params.oldValue;
  entity.newValue = event.params.newValue;
  entity.updatedBy = event.params.updatedBy;
  entity.timestamp = event.block.timestamp;
  entity.blockNumber = event.block.number;
  entity.transactionHash = event.transaction.hash;

  entity.save();
}
