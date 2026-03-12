# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oj do
  describe "JSON mimic mode" do
    it "loads Oj gem" do
      expect(described_class).to eq(Oj) # rubocop:disable RSpec/DescribedClass
    end

    it "overrides JSON.parse with Oj" do
      json_string = '{"key":"value","number":42}'
      result = JSON.parse(json_string)
      expect(result).to eq("key" => "value", "number" => 42)
    end

    it "overrides JSON.generate with Oj" do
      data = { key: "value", number: 42 }
      json_string = JSON.generate(data)
      parsed = JSON.parse(json_string)
      expect(parsed).to include("key" => "value", "number" => 42)
    end

    it "handles nested JSON structures" do
      nested = { tree: { did: "0xABCD", sensors: [ 1.2, 3.4, 5.6 ] } }
      round_tripped = JSON.parse(JSON.generate(nested))
      expect(round_tripped["tree"]["did"]).to eq("0xABCD")
      expect(round_tripped["tree"]["sensors"]).to eq([ 1.2, 3.4, 5.6 ])
    end

    it "raises JSON::ParserError on invalid JSON (via Oj mimic)" do
      expect { JSON.parse("not valid json") }.to raise_error(JSON::ParserError)
    end
  end

  describe "Blueprinter configuration" do
    it "uses Oj as the JSON generator" do
      expect(Blueprinter.configuration.generator).to eq(described_class)
    end
  end
end
