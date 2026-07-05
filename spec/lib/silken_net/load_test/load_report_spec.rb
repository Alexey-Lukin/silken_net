# frozen_string_literal: true

require "rails_helper"

RSpec.describe SilkenNet::LoadTest::LoadReport do
  describe ".percentiles" do
    it "рахує sorted-array перцентилі" do
      p = described_class.percentiles((1..100).to_a)
      expect(p["p50"]).to be_between(50, 51)
      expect(p["p99"]).to be_between(99, 100)
      expect(p["p99.9"]).to eq(100)
    end

    it "порожній вхід → {}" do
      expect(described_class.percentiles([])).to eq({})
    end
  end

  describe ".coefficient_of_variation" do
    it "0 для сталого ряду, велике для розкиданого" do
      expect(described_class.coefficient_of_variation([ 10, 10, 10 ])).to eq(0.0)
      expect(described_class.coefficient_of_variation([ 1, 100 ])).to be > 1
    end
  end

  describe ".littles_law" do
    it "L = λ·W" do
      expect(described_class.littles_law(arrival_rate: 10, mean_latency_s: 2)).to eq(20)
    end
  end

  describe ".coefficient_of_variation guards" do
    it "returns nil for fewer than two samples (variance undefined)" do
      expect(described_class.coefficient_of_variation([ 42 ])).to be_nil
      expect(described_class.coefficient_of_variation([])).to be_nil
    end

    it "returns nil when the mean is zero (guards divide-by-zero)" do
      expect(described_class.coefficient_of_variation([ -5, 5 ])).to be_nil
    end
  end

  describe ".classify_redis" do
    it "labels an empty / loopback URL as local" do
      expect(described_class.classify_redis("")).to eq("local")
      expect(described_class.classify_redis("redis://localhost:6379/0")).to eq("local")
      expect(described_class.classify_redis("redis://127.0.0.1:6379/0")).to eq("local")
    end

    it "labels an Upstash URL as networked" do
      expect(described_class.classify_redis("rediss://eu1.upstash.io:6379")).to eq("upstash(network)")
    end

    it "labels any other host as remote/other" do
      expect(described_class.classify_redis("redis://10.0.0.5:6379")).to eq("remote/other")
    end
  end

  describe ".environment_class + .banner" do
    it "класифікує вузьке місце й позначає dev як не-capacity" do
      env = described_class.environment_class
      expect(env).to include(:bottleneck_class, :capacity_valid, :db_rtt_us)
      # test-стек = local adapters → compute-bound, не capacity
      expect(env[:capacity_valid]).to be(false)
      expect(described_class.banner(env)).to include("BOTTLENECK-CLASS", "НЕ capacity")
    end

    # [INF.23 honesty-invariant] The prod-like stack (SolidCache + solid_cable + Upstash) is the
    # ONLY combination that marks a benchmark number as a true capacity ceiling — cover it directly.
    it "flags a prod-like IO-bound stack as capacity-valid (no dev-caveat in the banner)" do
      allow(Rails.cache).to receive(:class).and_return(instance_double(Class, name: "SolidCache::Store"))
      allow(described_class).to receive(:detect_cable_adapter).and_return("solid_cable")
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("REDIS_URL").and_return("rediss://eu1.upstash.io:6379")

      env = described_class.environment_class

      expect(env[:capacity_valid]).to be(true)
      expect(env[:bottleneck_class]).to include("io-bound (prod-like)")
      expect(described_class.banner(env)).not_to include("НЕ capacity")
    end
  end
end
