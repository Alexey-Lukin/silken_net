source "https://rubygems.org"

ruby "4.0.1"

gem "bcrypt"
gem "blueprinter"
gem "bootsnap", require: false
gem "eth"
gem "groupdate"
gem "image_processing"
gem "importmap-rails"
gem "kamal", require: false
gem "pagy"
gem "pg"
gem "phlex-rails"
gem "propshaft"
gem "puma"
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

gem "active_storage_validations"
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
  gem "rspec-rails"
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
