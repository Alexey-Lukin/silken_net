import { BigInt } from "@graphprotocol/graph-ts";
import {
  CarbonMinted,
  Slashed,
  PremiumPaid,
} from "../generated/SilkenCarbonCoin/SilkenCarbonCoin";
import {
  CarbonMintEvent,
  ProtocolFinancials,
  SlashingEvent,
  PremiumPaidEvent,
} from "../generated/schema";

function getProtocolFinancials(): ProtocolFinancials {
  let financials = ProtocolFinancials.load("1");
  if (financials == null) {
    financials = new ProtocolFinancials("1");
    financials.totalMinted = BigInt.zero();
    financials.totalBurned = BigInt.zero();
    financials.totalPremiums = BigInt.zero();
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
  entity.treeDid = event.params.treeDid;
  entity.timestamp = event.block.timestamp;
  entity.blockNumber = event.block.number;
  entity.transactionHash = event.transaction.hash;

  entity.save();

  let financials = getProtocolFinancials();
  financials.totalMinted = financials.totalMinted.plus(event.params.amount);
  financials.save();
}

export function handleSlashed(event: Slashed): void {
  let id =
    event.transaction.hash.toHexString() +
    "-" +
    event.logIndex.toString();
  let entity = new SlashingEvent(id);

  entity.target = event.params.target;
  entity.amount = event.params.amount;
  entity.treeDid = event.params.treeDid;
  entity.timestamp = event.block.timestamp;

  entity.save();

  let financials = getProtocolFinancials();
  financials.totalBurned = financials.totalBurned.plus(event.params.amount);
  financials.save();
}

export function handlePremiumPaid(event: PremiumPaid): void {
  let id =
    event.transaction.hash.toHexString() +
    "-" +
    event.logIndex.toString();
  let entity = new PremiumPaidEvent(id);

  entity.payer = event.params.payer;
  entity.amount = event.params.amount;
  entity.timestamp = event.block.timestamp;

  entity.save();

  let financials = getProtocolFinancials();
  financials.totalPremiums = financials.totalPremiums.plus(event.params.amount);
  financials.save();
}
