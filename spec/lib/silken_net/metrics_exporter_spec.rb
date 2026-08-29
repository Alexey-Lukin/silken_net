# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "net/http"

# Реальний HTTP-прохід (не мок): Puma::Server — внутрішній клас гема, його
# API-дрейф на bump'і має ламати CI, а не деплой мовчки.
RSpec.describe SilkenNet::MetricsExporter do
  it "serves the Prometheus registry on /metrics and 404s any other path" do
    server = described_class.start(port: 0, host: "127.0.0.1")
    expect(server).not_to be_nil

    port = server.connected_ports.first
    metrics = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/metrics"))
    expect(metrics.code).to eq("200")
    expect(metrics.body).to include("silkennet_")

    other = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/anything-else"))
    expect(other.code).to eq("404")
  ensure
    server&.stop(true)
  end

  it "returns nil instead of raising when the port is already taken" do
    blocker = TCPServer.new("127.0.0.1", 0)
    taken_port = blocker.addr[1]

    expect(described_class.start(port: taken_port, host: "127.0.0.1")).to be_nil
  ensure
    blocker&.close
  end

  it "still returns nil (no NameError) when the Sentry constant is unavailable" do
    hide_const("Sentry")
    blocker = TCPServer.new("127.0.0.1", 0)
    taken_port = blocker.addr[1]

    expect(described_class.start(port: taken_port, host: "127.0.0.1")).to be_nil
  ensure
    blocker&.close
  end
end
