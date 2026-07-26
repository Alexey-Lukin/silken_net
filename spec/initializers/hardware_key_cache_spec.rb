# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HARDWARE_KEY_CACHE initializer" do # rubocop:disable RSpec/DescribeClass
  it "defines the HARDWARE_KEY_CACHE constant" do
    expect(defined?(HARDWARE_KEY_CACHE)).to eq("constant")
  end

  it "is a SinLruRedux::ThreadSafeCache" do
    expect(HARDWARE_KEY_CACHE).to be_a(SinLruRedux::ThreadSafeCache)
  end

  it "has a max size of 10,000 entries" do
    expect(HARDWARE_KEY_CACHE.max_size).to eq(10_000)
  end

  describe "cache operations" do
    after do
      HARDWARE_KEY_CACHE.delete("test_device:v:123")
    end

    it "stores and retrieves binary key data" do
      binary_key = SecureRandom.random_bytes(32) # 256-bit AES key
      cache_key = "test_device:v:123"

      HARDWARE_KEY_CACHE[cache_key] = binary_key
      expect(HARDWARE_KEY_CACHE[cache_key]).to eq(binary_key)
    end

    it "returns nil for cache miss" do
      expect(HARDWARE_KEY_CACHE["nonexistent_key"]).to be_nil
    end

    it "supports delete operation" do
      HARDWARE_KEY_CACHE["test_device:v:123"] = "value"
      HARDWARE_KEY_CACHE.delete("test_device:v:123")
      expect(HARDWARE_KEY_CACHE["test_device:v:123"]).to be_nil
    end

    it "overwrites existing entries" do
      cache_key = "test_device:v:123"
      HARDWARE_KEY_CACHE[cache_key] = "old_value"
      HARDWARE_KEY_CACHE[cache_key] = "new_value"
      expect(HARDWARE_KEY_CACHE[cache_key]).to eq("new_value")
    end
  end

  describe "thread safety" do
    it "handles concurrent access without errors" do
      threads = 4.times.map do |i|
        Thread.new do
          10.times do |j|
            key = "thread_#{i}_key_#{j}"
            HARDWARE_KEY_CACHE[key] = SecureRandom.random_bytes(32)
            HARDWARE_KEY_CACHE[key]
            HARDWARE_KEY_CACHE.delete(key)
          end
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end
  end
end
