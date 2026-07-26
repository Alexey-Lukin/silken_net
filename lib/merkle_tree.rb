# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "digest"

# MerkleTree — спільний sha256-примітив Merkle-дерева (ARCH.12 Фаза 1).
#
# Контракт (запінено golden-векторами в spec/lib/merkle_tree_spec.rb):
# - Домен-розділення RFC 6962: лист = SHA256(0x00 ‖ data), вузол = SHA256(0x01 ‖ L ‖ R) —
#   інакше конкатенація двох дочірніх хешів невідрізненна від «листа» (підробний inclusion-proof).
# - Непарний вузол рівня ПРОМОТИТЬСЯ нагору без пари (НЕ дублюється — клас CVE-2012-2459).
# - Внутрішнє представлення = 64-hex lowercase РЯДКИ; вузли хешують ASCII-hex конкатенацію
#   (hash-of-hex). Це частина контракту: «оптимізація» на raw-байти тихо змінить усі корені.
# - Ієрархія (cluster-subtree → root) живе У СПОЖИВАЧАХ: субкорінь нижнього ярусу подається
#   верхньому ярусу як звичайний ЛИСТ; верифікація = verify() двічі, з перерахунком субкореня.
#   Примітив ярусів не знає.
#
# Без Rails і залежностей — юзабельний з scripts/verify_lineage_bundle.rb офлайн.
module MerkleTree
  LEAF_PREFIX = "\x00"
  NODE_PREFIX = "\x01"

  module_function

  # Корінь над упорядкованим набором листя (порядок = контракт споживача).
  # Порожній набір → nil (споживач вирішує семантику порожнього вікна сам).
  def root(leaves)
    return nil if leaves.empty?

    level = leaves.map { |leaf| leaf_hash(leaf) }
    level = combine(level) while level.size > 1
    level.first
  end

  # Inclusion-proof листа за індексом: масив кроків {"sibling" => 64hex, "side" => "left"|"right"},
  # де side — сторона СІБЛІНГА відносно поточного вузла. Промотовані рівні кроку не додають.
  def proof(leaves, index)
    unless index.is_a?(Integer) && index >= 0 && index < leaves.size
      raise ArgumentError, "index #{index.inspect} поза межами 0...#{leaves.size}"
    end

    path = []
    level = leaves.map { |leaf| leaf_hash(leaf) }
    i = index
    while level.size > 1
      sibling = i.even? ? i + 1 : i - 1
      path << { "sibling" => level[sibling], "side" => i.even? ? "right" : "left" } if sibling < level.size
      level = combine(level)
      i /= 2
    end
    path
  end

  # Перевірка proof-шляху; ключі кроків приймаються і рядкові, і символьні (JSON round-trip).
  def verify(leaf, proof, expected_root)
    return false if expected_root.nil?

    acc = leaf_hash(leaf)
    proof.each do |step|
      sibling = step["sibling"] || step[:sibling]
      side    = step["side"] || step[:side]
      return false unless sibling && %w[left right].include?(side)

      acc = side == "left" ? node_hash(sibling, acc) : node_hash(acc, sibling)
    end
    acc == expected_root
  end

  def leaf_hash(data)
    Digest::SHA256.hexdigest(LEAF_PREFIX + data.to_s)
  end

  def node_hash(left_hex, right_hex)
    Digest::SHA256.hexdigest(NODE_PREFIX + left_hex + right_hex)
  end

  def combine(level)
    level.each_slice(2).map { |left, right| right ? node_hash(left, right) : left }
  end
end
