# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "kamal"
require_relative "../support/repo_root"

# [INF.4] `config/deploy.yml` is the one deploy artefact NOTHING validated. YAML-parsing it
# proves only that it is well-formed text; whether KAMAL accepts it is a different question,
# and the answer was NO for an unknown length of time.
#
# 🔴 THE DEFECT THIS EXISTS FOR, measured 2026-08-31: the manifest carried
# `boot: { proxy: { publish: [...] } }`, and `Kamal::Configuration::Boot` accepts exactly
# `limit` · `wait` · `parallel_roles`. So EVERY kamal invocation died with
# `ERROR (Kamal::ConfigurationError): boot: unknown key: proxy` — i.e. `kamal deploy` on
# deploy day would not have reached SSH, let alone the registry. Reproduced against the
# previous commit, so it was shipped, not introduced. ⊕ It was also redundant even in a
# legal form: proxy ports are CLI options of `kamal proxy boot` whose defaults are the
# very 80/443 the block set.
#
# 🔑 Why nothing caught it: every existing deploy gate reads the manifest as TEXT
# (`deploy_secret_scan` greps, `env_fetch_declaration_spec` parses YAML) and none of them
# asks the TOOL. A config can be valid YAML, pass every regex, mirror every secret — and
# still be rejected by the only consumer that matters.
#
# 💰 Perimeter priced BEFORE switching on (00_05 §5): `kamal config` needs NO secrets — they
# resolve lazily, so a bare run exits 0 with an empty environment — and costs ~0.5 s per
# destination. Zero setup, ~1 s total.
#
# 🔒 DECLARED CEILING: this judges the config's SHAPE, never its VALUES. A perfectly valid
# manifest pointing at the wrong host, the wrong image or an unreachable server passes here.
# Declared at file scope (not inside the example group) so the examples can be generated from
# it without tripping RSpec/LeakyConstantDeclaration; prefixed to stay collision-free across specs.
KAMAL_DESTINATIONS = { "production" => nil, "canopy" => "canopy" }.freeze

RSpec.describe "config/deploy.yml is accepted by Kamal itself" do # rubocop:disable RSpec/DescribeClass
  def config_for(destination)
    Kamal::Configuration.create_from(
      config_file: REPO_ROOT.join("config/deploy.yml"),
      destination: destination
    )
  end

  KAMAL_DESTINATIONS.each do |slot, destination|
    it "loads without a ConfigurationError for #{slot}" do
      expect { config_for(destination) }.not_to raise_error
    end
  end

  describe "the origin-TLS contract [INF.4]" do
    # Both slots must present a certificate: Cloudflare is Full (strict) on both zones, and an
    # origin with no cert answers 521/525 on every request — a silent-origin failure, not a
    # boot crash, so nothing else would report it.
    KAMAL_DESTINATIONS.each do |slot, destination|
      it "carries a CUSTOM certificate (not ACME) on #{slot}" do
        proxy = config_for(destination).proxy
        expect(proxy.custom_ssl_certificate?).to be(true),
                                                 "#{slot}: proxy.ssl is not a custom cert pair — " \
                                                 "ACME cannot work under Full (strict) (INF.4)"
      end
    end

    # 🔴 The trap this pins is FRESH: the base `proxy:` block went live 2026-08-31, and
    # destination config DEEP-MERGES for hashes — so a canopy with no `proxy.host` of its own
    # silently inherits the PRODUCTION hostname and routes staging traffic on it.
    it "routes each slot on its OWN host" do
      hosts = KAMAL_DESTINATIONS.transform_values { |d| config_for(d).raw_config.dig("proxy", "host") }
      expect(hosts.values).to all(be_a(String))
      expect(hosts.values.uniq.size).to eq(2), "both slots route on the same host: #{hosts.inspect}"
      expect(hosts.fetch("canopy")).to start_with("canopy.")
    end
  end

  # ⚠️ Size pin: every example above is vacuous if the destination map is emptied or renamed,
  # and "no error raised" is the shape that goes green loudest on an empty set.
  it "judges both destinations, and both manifests exist" do
    expect(KAMAL_DESTINATIONS.size).to eq(2)
    expect(REPO_ROOT.join("config/deploy.yml")).to exist
    expect(REPO_ROOT.join("config/deploy.canopy.yml")).to exist
  end
end
