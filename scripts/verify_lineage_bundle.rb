#!/usr/bin/env ruby
# frozen_string_literal: true

#
# scripts/verify_lineage_bundle.rb — офлайн-верифікатор ISO lineage-bundle
# (ARCH.12/MRV.1). Pure Ruby, БЕЗ Rails/БД/мережі — аудитор ганяє його на
# власній машині проти bundle-файлу і довіряє лише on-chain кореням.
#
# Перевіряє для кожного листа:
#   1. leaf_cid == CidGenerator.cidv1(canonical payload)  (цілісність вмісту)
#   2. tier1: leaf_cid + path → ПЕРЕРАХОВАНИЙ субкорінь == заявленому
#   3. tier2: субкорінь + path → state_root якоря
# On-chain звірку state_root (etherscan_url) робить людина — це свідома межа
# офлайн-скрипта. pending_anchor / unprovable_regrouped = інформаційні, не фейли.
#
# Usage: ruby scripts/verify_lineage_bundle.rb bundle.json
# Exit: 0 = всі крипто-перевірки пройшли; 1 = будь-який mismatch.
#

require "json"
require "digest"
require_relative "../lib/merkle_tree"
require_relative "../app/services/filecoin/cid_generator"

abort "Usage: ruby scripts/verify_lineage_bundle.rb <bundle.json>" if ARGV.empty?

bundle = JSON.parse(File.read(ARGV[0]))
abort "Невідома схема: #{bundle['schema']}" unless bundle["schema"] == "silken.mrv.lineage.v1"

failures = []
anchored = 0
pending = 0
regrouped = 0
roots_to_check = {}

bundle.fetch("credits").each do |credit|
  tx_id = credit.dig("tx", "id")

  credit.fetch("leaves").each do |leaf|
    log_id = leaf.fetch("telemetry_log_id")

    # 1. Цілісність payload → CID
    recomputed_cid = Filecoin::CidGenerator.cidv1(leaf.fetch("payload"))
    unless recomputed_cid == leaf.fetch("leaf_cid")
      failures << "tx #{tx_id} / log #{log_id}: payload → CID mismatch (#{recomputed_cid} ≠ #{leaf['leaf_cid']})"
      next
    end

    proof = leaf.fetch("anchor_proof")
    case proof.fetch("status")
    when "pending_anchor" then pending += 1
    when "unprovable_regrouped" then regrouped += 1
    when "anchored"
      # 2. tier1: перерахований субкорінь МУСИТЬ збігтись із заявленим (анти-підміна ярусу)
      claimed_subroot = proof.dig("tier1", "subroot")
      unless MerkleTree.verify(leaf["leaf_cid"], proof.dig("tier1", "path"), claimed_subroot)
        failures << "tx #{tx_id} / log #{log_id}: tier1 path не веде до заявленого субкореня"
        next
      end
      # 3. tier2: субкорінь → state_root
      state_root = proof.dig("anchor", "state_root")
      unless MerkleTree.verify(claimed_subroot, proof.dig("tier2", "path"), state_root)
        failures << "tx #{tx_id} / log #{log_id}: tier2 path не веде до state_root якоря"
        next
      end
      anchored += 1
      roots_to_check[state_root] = proof.dig("anchor", "etherscan_url")
    else
      failures << "tx #{tx_id} / log #{log_id}: невідомий proof-статус #{proof['status']}"
    end
  end
end

puts "── Lineage bundle: #{bundle['credits'].size} credits " \
     "(org #{bundle.dig('organization', 'id')}, #{bundle.dig('period', 'from')}..#{bundle.dig('period', 'to')})"
puts "   leaves anchored=#{anchored} pending_anchor=#{pending} unprovable_regrouped=#{regrouped}"

unless roots_to_check.empty?
  puts "   Звір state_root(и) on-chain сам (StateRootAnchor):"
  roots_to_check.each { |root, url| puts "     #{root} → #{url || '(tx ще без etherscan-URL)'}" }
end

if failures.any?
  puts "✗ CRYPTO MISMATCH (#{failures.size}):"
  failures.each { |f| puts "   · #{f}" }
  exit 1
end

puts "✓ Всі крипто-перевірки пройшли (leaf-CID + tier1 + tier2)."
exit 0
