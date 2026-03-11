# frozen_string_literal: true

require "rails_helper"
require "eth"

RSpec.describe Web3::RpcConnectionPool do
  after do
    described_class.reset!
  end

  describe ".client_for" do
    it "returns an Eth::Client instance" do
      allow(ENV).to receive(:fetch).with("ALCHEMY_POLYGON_RPC_URL").and_return("https://polygon-rpc.example.com")
      allow(Eth::Client).to receive(:create).and_return(instance_double(Eth::Client))

      client = described_class.client_for("ALCHEMY_POLYGON_RPC_URL")
      expect(client).to be_present
    end

    it "caches the client per thread (same object returned)" do
      allow(ENV).to receive(:fetch).with("ALCHEMY_POLYGON_RPC_URL").and_return("https://polygon-rpc.example.com")
      client_double = instance_double(Eth::Client)
      allow(Eth::Client).to receive(:create).and_return(client_double)

      client1 = described_class.client_for("ALCHEMY_POLYGON_RPC_URL")
      client2 = described_class.client_for("ALCHEMY_POLYGON_RPC_URL")

      expect(client1).to equal(client2)
      expect(Eth::Client).to have_received(:create).once
    end

    it "creates separate clients for different RPC URLs" do
      allow(ENV).to receive(:fetch).with("ALCHEMY_POLYGON_RPC_URL").and_return("https://polygon-rpc.example.com")
      allow(ENV).to receive(:fetch).with("CELO_RPC_URL").and_return("https://celo-rpc.example.com")

      polygon_client = instance_double(Eth::Client, "polygon")
      celo_client = instance_double(Eth::Client, "celo")

      allow(Eth::Client).to receive(:create).with("https://polygon-rpc.example.com").and_return(polygon_client)
      allow(Eth::Client).to receive(:create).with("https://celo-rpc.example.com").and_return(celo_client)

      result_polygon = described_class.client_for("ALCHEMY_POLYGON_RPC_URL")
      result_celo = described_class.client_for("CELO_RPC_URL")

      expect(result_polygon).not_to equal(result_celo)
    end
  end

  describe ".reset!" do
    it "clears cached clients" do
      allow(ENV).to receive(:fetch).with("ALCHEMY_POLYGON_RPC_URL").and_return("https://polygon-rpc.example.com")
      client_double1 = instance_double(Eth::Client, "first")
      client_double2 = instance_double(Eth::Client, "second")

      allow(Eth::Client).to receive(:create).and_return(client_double1, client_double2)

      first_client = described_class.client_for("ALCHEMY_POLYGON_RPC_URL")
      described_class.reset!
      second_client = described_class.client_for("ALCHEMY_POLYGON_RPC_URL")

      expect(first_client).not_to equal(second_client)
      expect(Eth::Client).to have_received(:create).twice
    end
  end
end
