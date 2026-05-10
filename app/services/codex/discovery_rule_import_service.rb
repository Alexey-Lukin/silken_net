# frozen_string_literal: true

require "yaml"

module Codex
  # DiscoveryRuleImportService — idempotent UPSERT loader for
  # `db/seeds/codex/discovery_rules.yml`. Mirrors `NodeImportService` in
  # spirit: a YAML row → a `Codex::DiscoveryRule` keyed by `name`.
  #
  # Resolution rules:
  #   * `node_slug` → `Codex::Node` by slug (raises if missing).
  #   * `created_by_user_email` (optional) → `User` by email; falls back
  #     to `User.oracle_executioner` (system bot) when nil/unknown so a
  #     seed run never depends on a specific human account.
  #
  # Skipped silently (with a logger warn) when the target Node hasn't
  # been imported yet — this lets seeds run in any order. Subsequent
  # seed runs pick the rule up.
  class DiscoveryRuleImportService
    SEED_PATH = Rails.root.join("db/seeds/codex/discovery_rules.yml").freeze

    Result = Struct.new(:created, :updated, :skipped, keyword_init: true) do
      def success? = true
    end

    def self.call(path: SEED_PATH, logger: Rails.logger)
      new(path: path, logger: logger).call
    end

    def initialize(path:, logger:)
      @path   = path
      @logger = logger
    end

    def call
      return Result.new(created: 0, updated: 0, skipped: 0) unless File.exist?(@path)

      data = YAML.safe_load_file(@path, permitted_classes: []) || []
      created = updated = skipped = 0

      data.each do |row|
        node = ::Codex::Node.find_by(slug: row["node_slug"])
        unless node
          @logger.warn "[Codex::DiscoveryRuleImportService] node_slug=#{row['node_slug']} not found, skipping rule '#{row['name']}'"
          skipped += 1
          next
        end

        author = author_for(row["created_by_user_email"])
        rule = ::Codex::DiscoveryRule.find_or_initialize_by(name: row["name"])
        was_new = rule.new_record?

        rule.assign_attributes(
          codex_node_id:   node.id,
          condition_type:  row["condition_type"],
          threshold_value: row["threshold_value"],
          params:          row["params"] || {},
          active:          row.fetch("active", true),
          created_by_user: author
        )
        rule.save!

        was_new ? (created += 1) : (updated += 1)
      end

      Result.new(created: created, updated: updated, skipped: skipped)
    end

    private

    def author_for(email)
      (email.present? && ::User.find_by(email_address: email)) || ::User.oracle_executioner
    end
  end
end
