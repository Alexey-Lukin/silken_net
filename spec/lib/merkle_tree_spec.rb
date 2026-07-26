# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../../lib/merkle_tree"

# Golden vectors пінять контракт примітиву назавжди (ARCH.12): домен-префікси 0x00/0x01,
# promotion непарного вузла, hash-of-hex представлення. Зміна БУДЬ-ЯКОГО з них = інші корені
# по всьому проєкту (L1-якір, mint-lineage, офлайн-bundle) — вектори мусять зламатись.
RSpec.describe MerkleTree do
  let(:a) { "leaf-a" }
  let(:b) { "leaf-b" }
  let(:c) { "leaf-c" }

  describe ".root — golden vectors" do
    it "порожній набір → nil (семантика порожнього вікна — за споживачем)" do
      expect(described_class.root([])).to be_nil
    end

    it "один лист: корінь == leaf_hash (promotion-семантика)" do
      expect(described_class.root([ a ]))
        .to eq("539241082e7924f5647844d072a9f989ed31a6bf212d0613d057c620a739559e")
      expect(described_class.root([ a ])).to eq(described_class.leaf_hash(a))
    end

    it "пара листя" do
      expect(described_class.root([ a, b ]))
        .to eq("fd46985462e8399ed3762d1718b832e12a763d3fa9d129ddd5c48a4b39f0c83b")
    end

    it "трійка (непарний вузол промотиться, НЕ дублюється — анти-CVE-2012-2459)" do
      expect(described_class.root([ a, b, c ]))
        .to eq("77716f45d3b4dd57317cdcd5486fd4be9281241852e46bf79f0822392475d421")
    end

    it "CID-подібний лист нижнього ярусу (реалістичний формат)" do
      cid = "bafkreibm6jg3ux5qumhcn2b3flc3tyu6dmlb4xa7u5bf44yegnrjhc4yeq"
      expect(described_class.root([ cid, a ]))
        .to eq("4e073ed30332a5d77e5243ec2555558fb0419f10b77e5396130a8081e40da359")
    end
  end

  describe "домен-розділення (RFC 6962)" do
    it "leaf_hash ≠ голий SHA256 того самого рядка" do
      expect(described_class.leaf_hash(a)).not_to eq(Digest::SHA256.hexdigest(a))
    end

    it "корінь-як-лист ≠ сам корінь (двоярусна композиція без колізії ролей)" do
      pair_root = described_class.root([ a, b ])
      expect(described_class.root([ pair_root ]))
        .to eq("e9fa9dcd9603b06acf287b294d205ba254ffe92b54cff1dea36089f8a6dd23d0")
      expect(described_class.root([ pair_root ])).not_to eq(pair_root)
    end

    it "вузли хешують ASCII-hex конкатенацію (hash-of-hex — контракт, не деталь)" do
      expect(described_class.node_hash("aa", "bb"))
        .to eq(Digest::SHA256.hexdigest("\x01aabb"))
    end
  end

  describe ".proof / .verify" do
    it "золотий серіалізований proof-обʼєкт (JSON round-trip зі string-ключами)" do
      json = JSON.generate(described_class.proof([ a, b, c ], 0))
      expect(json).to eq(
        '[{"sibling":"01abc4445dc7e01188b0e606aa135dca25fe5b610e5ef36d8a37b78e6a026199","side":"right"},' \
        '{"sibling":"f20905290afa032250e422d668115a672bafff3cb07c71a243253af5d1bf8e43","side":"right"}]'
      )
      expect(described_class.verify(a, JSON.parse(json), described_class.root([ a, b, c ]))).to be true
    end

    it "промотований лист має коротший шлях (рівень без сібліга не додає кроку)" do
      path = described_class.proof([ a, b, c ], 2)
      expect(path.size).to eq(1)
      expect(path.first["side"]).to eq("left")
    end

    it "round-trip: кожен індекс кожного розміру 1..8 верифікується проти кореня" do
      (1..8).each do |n|
        leaves = (0...n).map { |i| "leaf-#{i}" }
        root = described_class.root(leaves)
        leaves.each_index do |i|
          expect(described_class.verify(leaves[i], described_class.proof(leaves, i), root))
            .to be(true), "n=#{n} i=#{i}"
        end
      end
    end

    it "приймає symbol-ключі кроків" do
      proof = described_class.proof([ a, b ], 0).map { |s| { sibling: s["sibling"], side: s["side"] } }
      expect(described_class.verify(a, proof, described_class.root([ a, b ]))).to be true
    end

    it "tamper: чужий лист / підмінений sibling / чужий корінь / nil-корінь → false" do
      leaves = [ a, b, c ]
      root = described_class.root(leaves)
      proof = described_class.proof(leaves, 1)
      expect(described_class.verify("intruder", proof, root)).to be false
      forged = [ { "sibling" => described_class.leaf_hash("intruder"), "side" => "left" } ]
      expect(described_class.verify(b, forged, root)).to be false
      expect(described_class.verify(b, proof, described_class.root([ a, b ]))).to be false
      expect(described_class.verify(b, proof, nil)).to be false
      expect(described_class.verify(b, [], root)).to be false
    end

    it "невалідний крок (без side/sibling) → false, не виняток" do
      root = described_class.root([ a, b ])
      expect(described_class.verify(a, [ { "side" => "up" } ], root)).to be false
      expect(described_class.verify(a, [ {} ], root)).to be false
    end

    it "out-of-range індекс → ArgumentError" do
      expect { described_class.proof([ a, b ], 2) }.to raise_error(ArgumentError)
      expect { described_class.proof([ a, b ], -1) }.to raise_error(ArgumentError)
      expect { described_class.proof([ a, b ], nil) }.to raise_error(ArgumentError)
    end
  end

  describe "властивості" do
    it "детермінізм і чутливість до порядку/вмісту на випадкових наборах" do
      rng = Random.new(1962) # фіксований seed — відтворюваний прогін
      3.times do
        leaves = (0...(2 + rng.rand(30))).map { rng.bytes(8).unpack1("H*") }
        root = described_class.root(leaves)
        expect(described_class.root(leaves)).to eq(root)
        expect(described_class.root(leaves.reverse)).not_to eq(root) if leaves.uniq.size > 1
        idx = rng.rand(leaves.size)
        expect(described_class.verify(leaves[idx], described_class.proof(leaves, idx), root)).to be true
      end
    end
  end
end
