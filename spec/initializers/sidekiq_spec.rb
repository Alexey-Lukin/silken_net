# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sidekiq initializer" do # rubocop:disable RSpec/DescribeClass
  describe "constants" do
    it "defines SIDEKIQ_REDIS_URL with default fallback" do
      expect(defined?(SIDEKIQ_REDIS_URL)).to be_truthy
      expect(SIDEKIQ_REDIS_URL).to be_a(String)
      expect(SIDEKIQ_REDIS_URL).to include("redis://")
    end

    it "defines SIDEKIQ_REDIS_POOL_SIZE as integer" do
      expect(defined?(SIDEKIQ_REDIS_POOL_SIZE)).to be_truthy
      expect(SIDEKIQ_REDIS_POOL_SIZE).to be_a(Integer)
      expect(SIDEKIQ_REDIS_POOL_SIZE).to be > 0
    end

    it "defines SIDEKIQ_REDIS_TIMEOUT as integer" do
      expect(defined?(SIDEKIQ_REDIS_TIMEOUT)).to be_truthy
      expect(SIDEKIQ_REDIS_TIMEOUT).to be_a(Integer)
      expect(SIDEKIQ_REDIS_TIMEOUT).to be > 0
    end
  end

  describe "default configuration values" do
    it "uses default pool size of 15 when ENV not set" do
      # Default from initializer: ENV.fetch("SIDEKIQ_REDIS_POOL_SIZE", 15)
      expect(SIDEKIQ_REDIS_POOL_SIZE).to eq(15)
    end

    it "uses default timeout of 5 when ENV not set" do
      # Default from initializer: ENV.fetch("SIDEKIQ_REDIS_TIMEOUT", 5)
      expect(SIDEKIQ_REDIS_TIMEOUT).to eq(5)
    end

    it "uses Redis DB 0 by default (not DB 1 reserved for Kredis)" do
      expect(SIDEKIQ_REDIS_URL).to match(%r{/0\z}).or match(%r{localhost:6379\z})
    end
  end
end
