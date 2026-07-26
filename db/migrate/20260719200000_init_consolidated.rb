# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = =====================================================================
# 🌱 INIT CONSOLIDATED — single squashed migration
# = =====================================================================
# This is THE only migration in the repository. All previous incremental
# migrations have been squashed into `db/structure.sql` since the project
# has no production database to preserve (pre-launch).
#
# Workflow for new clones:
#   bin/rails db:create db:schema:load db:seed
#
# Workflow for *adding* new migrations later:
#   bin/rails g migration AddXxx ...
#   bin/rails db:migrate
#   bin/rails db:schema:dump   # refreshes db/structure.sql
#
# Workflow for *another squash* later (post-launch — only if no prod):
#   1. `bin/rails db:schema:dump` to make sure structure.sql is current.
#   2. Delete every migration file *except this one*.
#   3. Rename this file's timestamp to a fresh one (e.g. now()).
#   4. Replace the schema_migrations INSERT block in structure.sql with
#      that single timestamp.
#   5. Bump StrongMigrations.start_after in
#      config/initializers/strong_migrations.rb to the new timestamp.
#
# Data seeding (system_parameters, organizations, oracle_executioner, ...)
# lives in db/seeds.rb and is invoked by `bin/rails db:seed`. Do NOT add
# data INSERTs to migrations — they belong in seeds or rake tasks
# (see lib/tasks/) so a fresh structure.sql never carries data.
class InitConsolidated < ActiveRecord::Migration[8.1]
  def up
    # Schema loaded from db/structure.sql via `bin/rails db:schema:load`.
    # `db:setup` runs schema:load then seed automatically; nothing to do
    # in code-form — this migration exists only as the schema_migrations
    # version anchor.
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
