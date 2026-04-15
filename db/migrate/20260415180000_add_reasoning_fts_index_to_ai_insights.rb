# frozen_string_literal: true

# The existing idx_ai_insights_reasoning_gin is a plain JSONB GIN index that only
# supports containment operators (@>, ?, ?|, ?&). It does NOT support efficient
# full-text search (ILIKE '%term%' causes Seq Scan on the entire table).
#
# This migration adds a dedicated tsvector GIN index on reasoning->>'description'
# for actual word-level full-text search capability. The existing JSONB GIN index
# is kept — it remains useful for structured containment queries.
class AddReasoningFtsIndexToAiInsights < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :ai_insights,
              "to_tsvector('simple', COALESCE(reasoning->>'description', ''))",
              using: :gin,
              name: :idx_ai_insights_reasoning_fts,
              algorithm: :concurrently
  end
end
