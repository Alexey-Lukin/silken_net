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
  CarbonMintEvent,
  ForestMintEvent,
  GovernanceSlashEvent,
  ProtocolFinancials,
  SlashingEvent,
} from "../generated/schema";

function getProtocolFinancials(): ProtocolFinancials {
  let financials = ProtocolFinancials.load("1");
  if (financials == null) {
    financials = new ProtocolFinancials("1");
    financials.totalMinted = BigInt.zero();
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
  entity.treeDid = event.params.treeDid;
  entity.archiveRoot = event.params.archiveRoot; // [E.60] dispatch archive-batch witness
  entity.timestamp = event.block.timestamp;
  entity.blockNumber = event.block.number;
  entity.transactionHash = event.transaction.hash;

  entity.save();

  let financials = getProtocolFinancials();
  financials.totalMinted = financials.totalMinted.plus(event.params.amount);
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
