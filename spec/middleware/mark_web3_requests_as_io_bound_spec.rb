# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "set"

# Pure-Rack middleware — no Rails autoload, no DB. Load directly so this spec
# does not depend on PostgreSQL being available.
require_relative "../../app/middleware/mark_web3_requests_as_io_bound"

RSpec.describe MarkWeb3RequestsAsIoBound do
  let(:downstream_app) { ->(_env) { [ 200, {}, [ "ok" ] ] } }
  let(:middleware) { described_class.new(downstream_app) }

  # The Puma "puma.mark_as_io_bound" key is normally set to a lambda by
  # Puma::Response BEFORE the Rack app runs. We simulate it here so we can
  # assert the middleware actually invokes the callback for matching paths.
  let(:io_bound_callback) { instance_double(Proc, call: nil) }

  def env_for(method:, path:, with_callback: true)
    {
      "REQUEST_METHOD" => method,
      "PATH_INFO" => path
    }.tap do |env|
      env["puma.mark_as_io_bound"] = io_bound_callback if with_callback
    end
  end

  describe "Web3 IO-bound endpoints" do
    it "marks POST /api/v1/oracle_callbacks as IO-bound" do
      expect(io_bound_callback).to receive(:call).once

      status, _, _ = middleware.call(env_for(method: "POST", path: "/api/v1/oracle_callbacks"))

      expect(status).to eq(200)
    end

    it "marks POST /api/v1/provisioning/register as IO-bound" do
      expect(io_bound_callback).to receive(:call).once

      status, _, _ = middleware.call(env_for(method: "POST", path: "/api/v1/provisioning/register"))

      expect(status).to eq(200)
    end
  end

  describe "non-IO-bound traffic" do
    it "does NOT mark unrelated POST endpoints" do
      expect(io_bound_callback).not_to receive(:call)

      middleware.call(env_for(method: "POST", path: "/api/v1/dashboard"))
    end

    it "does NOT mark GET requests on IO-bound paths (method is part of the match)" do
      expect(io_bound_callback).not_to receive(:call)

      middleware.call(env_for(method: "GET", path: "/api/v1/oracle_callbacks"))
    end

    it "does NOT mark a path with trailing slash" do
      expect(io_bound_callback).not_to receive(:call)

      middleware.call(env_for(method: "POST", path: "/api/v1/oracle_callbacks/"))
    end

    it "does NOT mark a path with extra suffix segments" do
      expect(io_bound_callback).not_to receive(:call)

      middleware.call(env_for(method: "POST", path: "/api/v1/oracle_callbacks/extra"))
    end

    it "does NOT mark a different API version (e.g. /api/v2)" do
      expect(io_bound_callback).not_to receive(:call)

      middleware.call(env_for(method: "POST", path: "/api/v2/oracle_callbacks"))
    end
  end

  describe "controller-level opt-in via silken_net.io_bound" do
    it "marks any request when env['silken_net.io_bound'] is truthy" do
      expect(io_bound_callback).to receive(:call).once

      env = env_for(method: "GET", path: "/api/v1/wallets/42/balance")
      env["silken_net.io_bound"] = true

      middleware.call(env)
    end
  end

  describe "non-Puma / Puma 7 backward compatibility" do
    it "is a no-op when env['puma.mark_as_io_bound'] is absent (rack-test, Falcon, dev)" do
      env = env_for(method: "POST", path: "/api/v1/oracle_callbacks", with_callback: false)

      expect { middleware.call(env) }.not_to raise_error
    end

    it "always forwards to the downstream app regardless of IO-bound match" do
      forwarded = []
      app = ->(env) { forwarded << env["PATH_INFO"]; [ 204, {}, [] ] }
      mw = described_class.new(app)

      mw.call(env_for(method: "POST", path: "/api/v1/oracle_callbacks"))
      mw.call(env_for(method: "GET",  path: "/up"))

      expect(forwarded).to eq([ "/api/v1/oracle_callbacks", "/up" ])
    end
  end
end
