# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class Codex::RealmBlueprint < Blueprinter::Base
  identifier :id

  fields :slug, :name_uk, :name_en, :glyph, :accent_token, :position, :is_active
  field(:nodes_count) { |realm, options| options[:nodes_counts]&.dig(realm.id) || 0 }
end
