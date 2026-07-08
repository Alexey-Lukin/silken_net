# frozen_string_literal: true

require "yaml"

# Codex::NodeImportService — idempotent UPSERT of Codex::Node + Codex::Realm
# seed records from YAML files at db/seeds/codex/.
#
# Why a service: Phase 1 ships 79 lore-records as YAML for diff-friendly PRs.
# Production seeding runs `db/seeds.rb` which calls this service after the
# User/Organization seeds. Re-running is safe — every record is keyed by
# its stable `slug`, and counters / battle state / counter caches are
# preserved on update.
#
# Inputs (YAML):
#   * realms.yml          — array of {slug, name_uk, name_en, glyph, accent_token, position, description_md}
#   * nodes/<realm>.yml   — array of node hashes; each MUST set `realm:`
#                            (the realm slug) and a globally unique `slug`.
#
# See docs/04_05_Codex_Lore_Module.md ADR-CDX-2 and ADR-CDX-3.
module Codex
  class NodeImportService
    Result = Struct.new(:realms_upserted, :nodes_upserted, :errors, keyword_init: true) do
      def success?
        errors.empty?
      end
    end

    SEED_ROOT = Rails.root.join("db/seeds/codex")

    NODE_FILES = {
      "ecosystem"   => "nodes/ecosystems.yml",
      "unique_tree" => "nodes/unique_trees.yml",
      "protocol"    => "nodes/protocols.yml",
      "mythos"      => "nodes/mythos.yml"
    }.freeze

    def self.call(root: SEED_ROOT, logger: Rails.logger)
      new(root: root, logger: logger).call
    end

    def initialize(root:, logger:)
      @root   = Pathname(root)
      @logger = logger
    end

    def call
      errors = []
      realms_count = 0
      nodes_count  = 0

      Codex::Realm.transaction do
        realms_count = upsert_realms!
      end

      NODE_FILES.each do |_realm_slug, rel_path|
        path = @root.join(rel_path)
        next unless path.exist?

        Codex::Node.transaction do
          nodes_count += upsert_nodes_from!(path)
        end
      rescue StandardError => e
        @logger.error("[Codex::NodeImportService] failed on #{rel_path}: #{e.class}: #{e.message}")
        errors << "#{rel_path}: #{e.message}"
      end

      Result.new(realms_upserted: realms_count, nodes_upserted: nodes_count, errors: errors)
    end

    private

    def upsert_realms!
      path = @root.join("realms.yml")
      return 0 unless path.exist?

      data = YAML.safe_load_file(path, permitted_classes: []) || []
      data.each do |attrs|
        slug = attrs.fetch("slug")
        realm = Codex::Realm.find_or_initialize_by(slug: slug)
        realm.assign_attributes(attrs.slice(
          "name_uk", "name_en", "glyph", "accent_token",
          "description_md", "position", "is_active"
        ).compact)
        # `is_active.nil?`-then dead: codex_realms.is_active = boolean NOT NULL DEFAULT true →
        # new_record вже true, ніколи nil; app-default = дубль schema-default (§B.4 leave).
        realm.is_active = true if realm.new_record? && realm.is_active.nil?
        realm.save!
      end
      data.size
    end

    def upsert_nodes_from!(path)
      data = YAML.safe_load_file(path, permitted_classes: []) || []
      now  = Time.current

      data.each do |attrs|
        slug       = attrs.fetch("slug")
        realm_slug = attrs.fetch("realm")
        realm = Codex::Realm.find_by!(slug: realm_slug)

        node = Codex::Node.find_or_initialize_by(slug: slug)
        node.realm = realm
        node.assign_attributes(attrs.slice(
          "codex_uid",
          "title_uk", "title_en", "subtitle_uk", "subtitle_en",
          "archetype_key",
          "context_md", "cyber_meaning_md", "lore_md",
          "latitude", "longitude", "geo_region",
          "lifecycle_status", "seed_origin",
          "external_refs", "discoverable_after_minutes"
        ).compact)
        # Mark provenance only on first import; preserve DAO/community origin
        # if a row was previously promoted via DAO.
        # `seed_origin.blank?`-then dead: seed_origin = integer NOT NULL DEFAULT 0 (="seed") →
        # new_record ніколи blank; app-default = дубль schema-default (§B.4 leave).
        node.seed_origin = "seed" if node.new_record? && node.seed_origin.blank?
        node.published_at ||= now
        node.save!
      end
      data.size
    end
  end
end
