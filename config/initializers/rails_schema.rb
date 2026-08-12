# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [KENOSIS TITAN]: Interactive HTML schema visualisation (development only)
# Gem: https://github.com/andrew2net/rails-schema
# Output: docs/schema.html — self-contained ER diagram, no server needed.
# Regenerate: rake rails_schema:generate

return unless defined?(Rails::Schema)

Rails::Schema.configure do |config|
  config.output_path = "docs/schema.html"
  config.title = "SilkenNet — Database Schema"
  config.theme = :dark
  config.expand_columns = false
  config.schema_format = :sql # project uses structure.sql (PostgreSQL partitioning)
  # Перелічуємо лише ті фреймворкові моделі, чиї engine ми справді вантажимо:
  # ActionMailbox/ActionText сюди не входять, бо їхніх engine немає в
  # `application.rb` взагалі [ARCH.79].
  config.exclude_models = [
    "ActiveStorage::Blob",
    "ActiveStorage::Attachment",
    "ActiveStorage::VariantRecord",
    "SolidCache::*",
    "SolidCable::*"
  ]
end
