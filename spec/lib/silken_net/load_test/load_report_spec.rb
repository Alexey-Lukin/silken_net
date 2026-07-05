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

  describe ".environment_class + .banner" do
    it "класифікує вузьке місце й позначає dev як не-capacity" do
      env = described_class.environment_class
      expect(env).to include(:bottleneck_class, :capacity_valid, :db_rtt_us)
      # test-стек = local adapters → compute-bound, не capacity
      expect(env[:capacity_valid]).to be(false)
      expect(described_class.banner(env)).to include("BOTTLENECK-CLASS", "НЕ capacity")
    end
  end
end
