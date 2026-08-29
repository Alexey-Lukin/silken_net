#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# scripts/verify_lineage_bundle.rb — офлайн-верифікатор ISO lineage-bundle
# (ARCH.12/MRV.1). Pure Ruby, БЕЗ Rails/БД/мережі — аудитор ганяє його на
# власній машині проти bundle-файлу і довіряє лише on-chain кореням.
#
# Крипто-перевірки (все — з самого файлу):
#   1. leaf_cid == CidGenerator.cidv1(canonical payload)  (цілісність вмісту)
#   2. payload.device_uid == tx.tree_did і payload.telemetry_log_id == leaf-id
#      (лист не «переїхав» з чужого дерева/запису)
#   3. sealed-кредит: MerkleTree.root(own-window листя) == telemetry_merkle_root
#      (набір і порядок листя прив'язані до кредиту, не issuer-asserted)
#   4. tier1: leaf_cid + path → ПЕРЕРАХОВАНИЙ субкорінь == заявленому
#   5. tier2: субкорінь + path → state_root якоря
#
# Межа довіри (свідома, задекларована): amount, ПОВНОТА набору кредитів/листя і
# континуїтет вікон — issuer-asserted (backstop = org AuditLog-ланцюг у leaf0).
# [DOC-T.89] `insurance_payouts` — емісія за ЗБИТОК, НЕ вуглецеві кредити: крипто під
# нею немає за конструкцією (немає листя), тож тут вона лише ПЕРЕЛІЧУЄТЬСЯ вголос.
# Мовчазна секція гірша за відсутню: аудитор прийняв би її за перевірену.
# On-chain звірка state_root — людина: tx МУСИТЬ таргетити канонічний
# StateRootAnchor-контракт; адресу `anchor_contract` звіряй з НЕЗАЛЕЖНИМ
# джерелом (канон проєкту / офіційний сайт), не з цим файлом.
#
# Usage: ruby scripts/verify_lineage_bundle.rb bundle.json
# Exit: 0 = всі крипто-перевірки пройшли; 1 = будь-який mismatch.
#

require "json"
require "digest"
require "bigdecimal"
require_relative "../lib/merkle_tree"
require_relative "../app/services/filecoin/cid_generator"

abort "Usage: ruby scripts/verify_lineage_bundle.rb <bundle.json>" if ARGV.empty?

# Анти-smuggling: JSON з дубль-ключами (людина бачить перший, парсер бере
# останній) відкидається на вході — класика атак на JSON-верифікатори.
# ДВОШАРОВО: json ≥ 2.20 — нативний `allow_duplicate_key: false` (C-парсер
# дедуплікує ДО виклику []=, тож object_class-override там СЛІПИЙ — fable №2
# емпірично); старші json опцію мовчки ігнорують, але їхній парсер кличе []=
# на кожен ключ → StrictHash ловить. Захист не залежить від версії на машині
# аудитора.
class StrictHash < Hash
  def []=(key, value)
    raise JSON::ParserError, "duplicate JSON key: #{key.inspect}" if key?(key)

    super
  end
end

begin
  bundle = JSON.parse(File.read(ARGV[0]), object_class: StrictHash, allow_duplicate_key: false)
rescue JSON::ParserError => e
  abort "✗ Bundle відхилено: #{e.message}"
end
abort "Невідома схема: #{bundle['schema']}" unless bundle["schema"] == "silken.mrv.lineage.v1"

failures = []
anchored = 0
pending = 0
regrouped = 0
diverged = 0
total_leaves = 0
sealed_credits = 0
unsealed_credits = 0
roots_to_check = {}

bundle.fetch("credits").each do |credit|
  tx_id = credit.dig("tx", "id")
  tree_did = credit.dig("tx", "tree_did")

  credit.fetch("leaves").each do |leaf|
    total_leaves += 1
    log_id = leaf.fetch("telemetry_log_id")
    payload = leaf.fetch("payload")

    # 1. Цілісність payload → CID
    recomputed_cid = Filecoin::CidGenerator.cidv1(payload)
    unless recomputed_cid == leaf.fetch("leaf_cid")
      failures << "tx #{tx_id} / log #{log_id}: payload → CID mismatch (#{recomputed_cid} ≠ #{leaf['leaf_cid']})"
      next
    end

    # 2. Лист прив'язаний до дерева кредиту і до власного запису
    unless payload["device_uid"] == tree_did
      failures << "tx #{tx_id} / log #{log_id}: payload.device_uid #{payload['device_uid'].inspect} ≠ tx.tree_did #{tree_did.inspect}"
    end
    unless payload["telemetry_log_id"] == log_id
      failures << "tx #{tx_id} / log #{log_id}: payload.telemetry_log_id #{payload['telemetry_log_id'].inspect} ≠ leaf-id"
    end

    proof = leaf.fetch("anchor_proof")
    case proof.fetch("status")
    when "pending_anchor" then pending += 1
    when "unprovable_regrouped" then regrouped += 1
    when "subroot_diverged"
      # [ARCH.70 ⚖️ 2026-08-29] Окремий рахунок, але НЕ падіння — і це присуд,
      # не поблажливість. Розбіжність субкореня однаково настає від легітимного
      # переїзду дерева між кластерами і від підміни payload'а; емітент причину
      # не ізолює (стеля названа в `Mrv::LineageReportService`). Падати на
      # неоднозначному факті означало б стверджувати tamper без доказу — рівно
      # той клас, проти якого будувався весь тракт.
      diverged += 1
    when "anchored"
      # 4. tier1: перерахований субкорінь МУСИТЬ збігтись із заявленим (анти-підміна ярусу)
      claimed_subroot = proof.dig("tier1", "subroot")
      unless MerkleTree.verify(leaf["leaf_cid"], proof.dig("tier1", "path"), claimed_subroot)
        failures << "tx #{tx_id} / log #{log_id}: tier1 path не веде до заявленого субкореня"
        next
      end
      # 5. tier2: субкорінь → state_root
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

  # 3. Sealed-кредит: mint-root перераховується з own-window листя (канонічний порядок
  # = порядок масиву; підміна набору/порядку/листа → mismatch)
  if credit["seal"] == "sealed"
    sealed_credits += 1
    own_cids = credit["leaves"].select { |l| l["window_source"] == tx_id }.map { |l| l["leaf_cid"] }
    recomputed_root = MerkleTree.root(own_cids)
    unless recomputed_root == credit["telemetry_merkle_root"]
      failures << "tx #{tx_id}: mint-root mismatch (перераховано #{recomputed_root.inspect}, " \
                  "заявлено #{credit['telemetry_merkle_root'].inspect}) — набір/порядок листя " \
                  "підмінено АБО пізній commit/ретеншн-дроп (05_04 GRACE-residual)"
    end
  else
    unsealed_credits += 1
  end
end

puts "── Lineage bundle: #{bundle['credits'].size} credits " \
     "(org #{bundle.dig('organization', 'id')}, #{bundle.dig('period', 'from')}..#{bundle.dig('period', 'to')})"
puts "   leaves anchored=#{anchored} pending_anchor=#{pending} unprovable_regrouped=#{regrouped} subroot_diverged=#{diverged} · " \
     "credits sealed=#{sealed_credits} unsealed=#{unsealed_credits}"

# [DOC-T.89] Страхові виплати: НЕ верифікуються (нічого верифікувати) — але й НЕ
# замовчуються. М'яке читання замість `fetch` свідомо: bundle без секції (старіший
# випуск) лишається валідним, а не падає на відсутньому ключі.
payouts = bundle["insurance_payouts"]
payouts = [] unless payouts.is_a?(Array)
if payouts.any?
  # 💰 Сума ГРУПУЄТЬСЯ за `token_type` і друкується З ОДИНИЦЕЮ: рядки різних токенів —
  # різні шкали, і зведення їх в одне число тут було б тим самим класом дефекту, який
  # ця секція лікує ярусом вище. BigDecimal, а не Float: це аудиторський артефакт.
  totals = payouts.group_by { |p| p.dig("tx", "token_type") }
                  .map { |token, rows| "#{rows.sum { |r| BigDecimal(r.dig('tx', 'amount').to_s) }.to_s('F')} #{token}" }
                  .join(" + ")
  puts "   ⚠️  insurance_payouts=#{payouts.size} (Σ #{totals}): емісія за ЗБИТОК, НЕ вуглецеві " \
       "кредити — lineage під ними НЕМАЄ за конструкцією, крипто-перевірок тут НУЛЬ. " \
       "On-chain вони несуть префікс `INS_`; звіряй суму з subgraph " \
       "`ProtocolFinancials.totalMintedInsurance`."
end

if unsealed_credits.positive?
  puts "   ⚠️  #{unsealed_credits} unsealed-кредит(и): mint-root-binding для них НЕ перевірявся " \
       "(nil-root = легітимний fail-open, але аудит мусить це БАЧИТИ, не пропустити мовчки)."
end

if anchored.zero? && total_leaves.positive?
  puts "   ⚠️  ЖОДЕН лист не заякорений — ланцюг до on-chain кореня НЕ перевірявся " \
       "(pending/regrouped-статуси легітимні для свіжих даних, але аудит без якоря неповний)."
end

unless roots_to_check.empty?
  contract = bundle["anchor_contract"]
  puts "   Звір state_root(и) on-chain сам (StateRootAnchor):"
  puts "   ⚠️  tx МУСИТЬ таргетити контракт #{contract || '(anchor_contract не задано — pre-deploy)'}" \
       " — адресу звіряй з НЕЗАЛЕЖНИМ джерелом (канон/сайт), не з цим файлом."
  roots_to_check.each { |root, url| puts "     #{root} → #{url || '(tx ще без etherscan-URL)'}" }
end

if failures.any?
  puts "✗ CRYPTO MISMATCH (#{failures.size}):"
  failures.each { |f| puts "   · #{f}" }
  exit 1
end

puts "✓ Всі крипто-перевірки пройшли (leaf-CID + did-binding + mint-root + tier1 + tier2)."
exit 0
