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
  config.exclude_models = [
    "ActiveStorage::Blob",
    "ActiveStorage::Attachment",
    "ActiveStorage::VariantRecord",
    "ActionMailbox::*",
    "ActionText::*",
    "SolidCache::*",
    "SolidQueue::*",
    "SolidCable::*"
  ]
end
