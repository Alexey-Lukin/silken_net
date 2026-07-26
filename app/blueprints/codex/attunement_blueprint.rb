# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class Codex::AttunementBlueprint < Blueprinter::Base
  identifier :id

  fields :user_id, :codex_node_id, :intensity, :quote, :started_at, :created_at
end
