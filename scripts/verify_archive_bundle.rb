#!/usr/bin/env ruby
# frozen_string_literal: true

#
# scripts/verify_archive_bundle.rb — офлайн-верифікатор телеметрія-архів-батчу
# (E.60 Фаза 1б). Pure Ruby, БЕЗ Rails/БД/мережі — аудитор ганяє його проти
# запіненого артефакту (JSON з IPFS) і довіряє лише on-chain кореням.
# Сіблінг scripts/verify_lineage_bundle.rb (ISO lineage); той верифікує
# credit→state_root ланцюг, цей — archive_root мінт-диспатчу.
#
# Крипто-перевірки (все — з самого файлу):
#   1. leaf_cid == CidGenerator.cidv1(canonical payload)  (цілісність вмісту)
#   2. MerkleTree.root(leaf_cids У ПОРЯДКУ МАСИВУ) == archive_root
#      (канонічний порядок = глобальний (created_at, id) asc — підміна
#      набору/порядку/листа → mismatch)
#   3. window-binding: кожен лист ∈ РІВНО ОДНЕ вікно tx свого дерева
#      (0 вікон = smuggled leaf; >1 = зламаний курсор-інваріант)
#
# Межа довіри (свідома, задекларована — дзеркало artifact.verification_instructions):
# amount кожної tx (growth_points у leaf v1 НЕМАЄ — leaf = Z), ПОВНОТА набору
# tx/листя, відповідність archive_root → ipfs_cid (discovery через реєстр
# issuer'а) — issuer-asserted. Root = свідок evidence-набору ДИСПАТЧУ (N:1):
# вікна не-мінтованих tx (failed/poisoned/KYC-skip) присутні легально.
# On-chain звірка — людина: archiveRoot = indexed topic подій CarbonMinted/
# ForestMinted; contract-адресу звіряй з НЕЗАЛЕЖНИМ джерелом, не з цим файлом.
#
# Usage: ruby scripts/verify_archive_bundle.rb artifact.json
# Exit: 0 = всі крипто-перевірки пройшли; 1 = будь-який mismatch.
#

require "json"
require "digest"
require_relative "../lib/merkle_tree"
require_relative "../app/services/filecoin/cid_generator"

abort "Usage: ruby scripts/verify_archive_bundle.rb <artifact.json>" if ARGV.empty?

# Анти-smuggling дубль-ключів — той самий двошаровий захист, що в сіблінга
# (json ≥ 2.20 нативно; старші — через StrictHash#[]=).
class StrictHash < Hash
  def []=(key, value)
    raise JSON::ParserError, "duplicate JSON key: #{key.inspect}" if key?(key)

    super
  end
end

begin
  artifact = JSON.parse(File.read(ARGV[0]), object_class: StrictHash, allow_duplicate_key: false)
rescue JSON::ParserError => e
  abort "✗ Artifact відхилено: #{e.message}"
end

unless artifact["kind"] == "silkennet-telemetry-archive-batch" && artifact["artifact_version"] == 1
  abort "Невідома схема: kind=#{artifact['kind'].inspect} version=#{artifact['artifact_version'].inspect}"
end

failures = []
archive_root = artifact.fetch("archive_root")
leaves = artifact.fetch("leaves")
txs = artifact.fetch("transactions")

# 1. Цілісність кожного листа: payload → CID
leaf_cids = leaves.each_with_index.map do |leaf, i|
  payload = leaf.fetch("payload")
  recomputed = Filecoin::CidGenerator.cidv1(payload)
  unless recomputed == leaf.fetch("leaf_cid")
    failures << "leaf ##{i} (log #{payload['telemetry_log_id']}): payload → CID mismatch " \
                "(#{recomputed} ≠ #{leaf['leaf_cid']})"
  end
  leaf.fetch("leaf_cid")
end

# 2. Корінь над листям У ПОРЯДКУ МАСИВУ == archive_root
recomputed_root = MerkleTree.root(leaf_cids)
unless recomputed_root == archive_root
  failures << "archive_root mismatch: перераховано #{recomputed_root.inspect}, " \
              "заявлено #{archive_root.inspect} — набір/порядок/вміст листя підмінено"
end

# 3. Window-binding: лист ∈ рівно одне вікно tx СВОГО дерева.
# Порівняння tuple (created_at, id): ISO-8601(6) UTC-рядки однакової точності
# порівнюються лексикографічно коректно; межі (from — ексклюзивна, to — інклюзивна)
# — дзеркало Mrv::LineageWindow.
windowed_txs = txs.select { |tx| tx.dig("window", "to_at") }
leaves.each_with_index do |leaf, i|
  payload = leaf.fetch("payload")
  key = [ payload.fetch("created_at"), payload.fetch("telemetry_log_id") ]
  covering = windowed_txs.select do |tx|
    next false unless tx["tree_did"] == payload["device_uid"]

    w = tx.fetch("window")
    upper = [ w.fetch("to_at"), w.fetch("to_id") ]
    lower = w["from_at"] ? [ w["from_at"], w["from_id"] ] : nil
    (key <=> upper) <= 0 && (lower.nil? || (key <=> lower).positive?)
  end
  case covering.size
  when 1 then nil
  when 0
    failures << "leaf ##{i} (log #{payload['telemetry_log_id']}, did #{payload['device_uid']}): " \
                "НЕ покритий жодним tx-вікном свого дерева — smuggled leaf"
  else
    failures << "leaf ##{i} (log #{payload['telemetry_log_id']}): покритий #{covering.size} вікнами " \
                "(overlap — зламаний watermark-курсор)"
  end
end

statuses = txs.group_by { |tx| tx["status_at_pin"] }.transform_values(&:size)
puts "── Archive batch: root #{archive_root[0, 16]}… · #{artifact['token_type']} · " \
     "#{leaves.size} leaves · #{txs.size} txs #{statuses.inspect}"
puts "   leaf_version=#{artifact['leaf_version']} order=#{artifact['leaf_order']} " \
     "tax_rate=#{artifact['tax_rate_applied'].inspect}"

non_minted = txs.reject { |tx| %w[sent confirmed].include?(tx["status_at_pin"]) }
if non_minted.any?
  puts "   ℹ️  N:1: #{non_minted.size} tx НЕ у sent/confirmed на момент піну — їхні вікна в бандлі " \
       "легальні (root = свідок ДИСПАТЧУ, не 1:1 мінта)."
end

puts "   Звір root on-chain сам: archiveRoot = indexed topic CarbonMinted/ForestMinted; " \
     "contract-адресу — з НЕЗАЛЕЖНОГО джерела (канон/сайт), НЕ з цього файла."
puts "   ISSUER-ASSERTED (не верифіковано тут): amount'и, повнота набору, root→ipfs_cid discovery."

if failures.any?
  puts "✗ CRYPTO MISMATCH (#{failures.size}):"
  failures.each { |f| puts "   · #{f}" }
  exit 1
end

puts "✓ Всі крипто-перевірки пройшли (leaf-CID + archive_root + window-binding)."
exit 0
