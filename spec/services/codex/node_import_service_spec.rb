# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::NodeImportService do
  let(:tmpdir) { Pathname(Dir.mktmpdir("codex-import")) }

  after { FileUtils.rm_rf(tmpdir) }

  def write(rel, body)
    path = tmpdir.join(rel)
    FileUtils.mkdir_p(path.dirname)
    path.write(body)
  end

  describe ".call" do
    it "returns Result with success? true on empty seed dir" do
      result = described_class.call(root: tmpdir)
      expect(result).to be_success
      expect(result.realms_upserted).to eq(0)
      expect(result.nodes_upserted).to eq(0)
    end

    it "upserts realms and nodes from minimal YAML" do
      write("realms.yml", <<~YML)
        - slug: ecosystem
          name_uk: Екосистеми
          name_en: Ecosystems
          glyph: forest
          accent_token: gaia-primary
          position: 1
          description_md: "Test realm."
      YML
      write("nodes/ecosystems.yml", <<~YML)
        - slug: test-bir
          realm: ecosystem
          codex_uid: CDX-ECO-9001
          title_uk: Тест-бір
          title_en: Test Forest
          archetype_key: ecosystem_genesis_cluster
          lifecycle_status: 3
          context_md: ""
          cyber_meaning_md: ""
      YML

      result = described_class.call(root: tmpdir)

      expect(result).to be_success
      expect(result.realms_upserted).to eq(1)
      expect(result.nodes_upserted).to eq(1)
      expect(Codex::Realm.find_by(slug: "ecosystem")).to be_present
      expect(Codex::Node.find_by(slug: "test-bir").title_en).to eq("Test Forest")
    end

    it "is idempotent on re-run (same counts, no duplicates)" do
      write("realms.yml", <<~YML)
        - slug: ecosystem
          name_uk: E
          name_en: E
          glyph: forest
          accent_token: gaia-primary
          position: 1
      YML
      write("nodes/ecosystems.yml", <<~YML)
        - slug: re-run-node
          realm: ecosystem
          codex_uid: CDX-ECO-9100
          title_uk: A
          title_en: A
          archetype_key: ecosystem_genesis_cluster
      YML

      2.times { described_class.call(root: tmpdir) }

      expect(Codex::Realm.where(slug: "ecosystem").count).to eq(1)
      expect(Codex::Node.where(slug: "re-run-node").count).to eq(1)
    end

    it "preserves DAO seed_origin on subsequent runs" do
      write("realms.yml", <<~YML)
        - slug: ecosystem
          name_uk: E
          name_en: E
          glyph: forest
          accent_token: gaia-primary
          position: 1
      YML
      write("nodes/ecosystems.yml", <<~YML)
        - slug: dao-promoted
          realm: ecosystem
          codex_uid: CDX-ECO-9200
          title_uk: A
          title_en: A
          archetype_key: ecosystem_genesis_cluster
      YML

      described_class.call(root: tmpdir)
      Codex::Node.find_by(slug: "dao-promoted").update!(seed_origin: "dao_proposal")

      described_class.call(root: tmpdir)

      expect(Codex::Node.find_by(slug: "dao-promoted").seed_origin).to eq("dao_proposal")
    end

    it "captures errors per file without aborting the whole import" do
      write("realms.yml", "[]")
      write("nodes/ecosystems.yml", <<~YML)
        - slug: bad-realm-ref
          realm: nonexistent_realm
          codex_uid: CDX-ECO-9300
          title_uk: X
          title_en: X
          archetype_key: ecosystem_genesis_cluster
      YML

      result = described_class.call(root: tmpdir)

      expect(result).not_to be_success
      expect(result.errors.first).to include("nodes/ecosystems.yml")
    end

    it "loads the canonical 79-record corpus from the default SEED_ROOT" do
      # Intentional non-hermetic guardrail: this example loads the actual
      # `db/seeds/codex/*.yml` files and asserts the curated corpus
      # (4 realms + 79 nodes) is intact. Failure here means the lore
      # corpus has been corrupted or accidentally trimmed — surface that
      # immediately rather than silently shipping a half-empty Codex.
      result = described_class.call
      expect(result).to be_success
      expect(result.realms_upserted).to eq(4)
      expect(result.nodes_upserted).to eq(79)
    end
  end
end
