import { BigInt } from "@graphprotocol/graph-ts";
import { CarbonMinted } from "../generated/SilkenCarbonCoin/SilkenCarbonCoin";
import { CarbonMintEvent } from "../generated/schema";

export function handleCarbonMinted(event: CarbonMinted): void {
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let entity = new CarbonMintEvent(id);

  entity.to = event.params.investor;
  entity.amount = event.params.amount;
  entity.treeDid = event.params.treeDid;
  entity.timestamp = event.block.timestamp;
  entity.blockNumber = event.block.number;
  entity.transactionHash = event.transaction.hash;

  entity.save();
}
