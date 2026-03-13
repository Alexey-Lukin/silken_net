source "https://rubygems.org"

# = ===================================================================
# 💎 RUBY & RAILS (Core Platform)
# = ===================================================================
ruby "4.0.1"

gem "rails", "~> 8.1.2"

# = ===================================================================
# 📦 PRODUCTION GEMS (Alphabetical)
# = ===================================================================
gem "aasm"
gem "active_storage_validations"
gem "argon2id"
gem "aws-sdk-s3", require: false            # Active Storage: S3-compatible (AWS, MinIO, DigitalOcean Spaces, Backblaze B2)
gem "blueprinter"
gem "bootsnap", require: false
gem "csv"
gem "ed25519"
gem "eth"
gem "google-cloud-storage", require: false   # Active Storage: Google Cloud Storage (mirror / disaster recovery)
gem "groupdate"
gem "httpx"
gem "image_processing"
gem "importmap-rails"
gem "kamal", require: false
gem "kredis"
gem "oj"
gem "pagy"
gem "pg"
gem "phlex-rails"
gem "prawn"
gem "prawn-table"
gem "prometheus-client"
gem "propshaft"
gem "puma"
gem "pundit"
gem "rack-attack"
gem "sidekiq"
gem "sidekiq-scheduler"
gem "solid_cable"
gem "solid_cache"
gem "solid_queue"
gem "stimulus-rails"
gem "strong_migrations"
gem "tailwindcss-rails"
gem "thruster", require: false
gem "turbo-rails"
gem "tzinfo-data", platforms: %i[ windows jruby ]

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
