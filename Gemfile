source "https://rubygems.org"

ruby "4.0.1"

gem "argon2id"
gem "blueprinter"
gem "bootsnap", require: false
gem "csv"
gem "eth"
gem "groupdate"
gem "image_processing"
gem "importmap-rails"
gem "kamal", require: false
gem "oj"
gem "pagy"
gem "pg"
gem "phlex-rails"
gem "prawn"
gem "prawn-table"
gem "propshaft"
gem "puma"
gem "pundit"
gem "rails", "~> 8.1.2"
gem "sidekiq"
gem "sidekiq-scheduler"
gem "solid_cable"
gem "solid_cache"
gem "solid_queue"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "thruster", require: false
gem "turbo-rails"
gem "tzinfo-data", platforms: %i[ windows jruby ]

gem "aasm"
gem "active_storage_validations"
gem "strong_migrations"
# Active Storage: cloud object storage backends
# S3-compatible (AWS, MinIO, DigitalOcean Spaces, Backblaze B2)
gem "aws-sdk-s3", require: false
# Google Cloud Storage (mirror / disaster recovery)
gem "google-cloud-storage", require: false

group :development, :test do
  gem "brakeman", require: false
  gem "bundler-audit", require: false
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "factory_bot_rails"
  gem "pg_query"
  gem "prosopite"
  gem "rspec-rails"
  gem "rubocop-rails-omakase", require: false
  gem "rubocop-rspec", require: false
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "cuprite"
  gem "parallel_tests"
  gem "simplecov", require: false
end
