# frozen_string_literal: true

require "rails_helper"

# INF.16 regression guard — the production multi-DB set must resolve so EVERY logical
# database inherits host+credentials from &default. The original first-deploy fail was a
# component DB (cache/cable) left host+creds-less (DATABASE_URL merged into primary only);
# the component-style fix makes all three share one anchor. This asserts the invariant
# OFFLINE (config resolution, no live DB) so a future edit that drops a component off
# &default — or re-adds a DB creds-less — fails in CI, not silently on first boot.
# (The live half — Postgres accepting the connection + db:prepare creating each schema —
# stays a deploy-day 👤 check; here we guard the config shape only.)
RSpec.describe "production database.yml configuration" do # rubocop:disable RSpec/DescribeClass
  subject(:configs) { ActiveRecord::Base.configurations.configs_for(env_name: "production") }

  it "resolves exactly the primary/cache/cable set (Solid Queue pruned — INF.18)" do
    expect(configs.map(&:name)).to contain_exactly("primary", "cache", "cable")
  end

  it "every logical DB inherits host+username+password from &default (INF.16 — none left creds-less)" do
    shared = configs.map { |c| c.configuration_hash.values_at(:host, :username, :password) }
    expect(shared.uniq.size).to eq(1)
  end

  it "secondaries derive their name from primary — one POSTGRES_DATABASE switches all 3 (canopy isolation)" do
    by_name = configs.to_h { |c| [ c.name, c.configuration_hash[:database] ] }
    expect(by_name["cache"]).to eq("#{by_name['primary']}_cache")
    expect(by_name["cable"]).to eq("#{by_name['primary']}_cable")
  end
end
