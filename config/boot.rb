ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "dotenv/load"   # Load .env before Rails evaluates database.yml ERB.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
