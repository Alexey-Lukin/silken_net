# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "pg"

# The Solid Cache / Solid Cable databases are created by the web entrypoint's `db:prepare`
# on a cold deploy, and the schema it loads into each is the file Rails DERIVES for that
# config and format — `schema_format = :sql` ⇒ `db/<name>_structure.sql`. Until 2026-09-02
# the repo carried only the installers' `<name>_schema.rb`, which the SQL format never
# reads: both databases came up EMPTY on the first canopy boot, `Rails.cache` in db/seeds
# died on `solid_cache_entries`, and the restarted container went healthy on `/up` over a
# half-seeded slot. dev/test never see this (cache lives in primary, cable is async), so the
# only place it could fail was the first production-shaped boot — this spec moves it here.
#
# 🔒 Declared ceiling: the round-trip loads each file into a throwaway database on the test
# server (needs `psql` on PATH, as `db:prepare` itself does) and checks the table exists —
# it proves the file is loadable and complete, not that the entrypoint runs it.
RSpec.describe "Solid Cache / Solid Cable structure files" do # rubocop:disable RSpec/DescribeClass
  { "cache" => "solid_cache_entries", "cable" => "solid_cable_messages" }.each do |name, table|
    it "commits the file Rails derives for the production `#{name}` config (`#{name}_structure.sql`)" do
      db_config = ActiveRecord::Base.configurations.configs_for(env_name: "production", name: name)
      derived = ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(db_config, :sql)
      aggregate_failures do
        expect(File.basename(derived)).to eq("#{name}_structure.sql")
        expect(File).to exist(derived), "#{derived} missing — `db:prepare` would create an EMPTY #{name} database"
        expect(File.read(derived)).to include("CREATE TABLE public.#{table} (")
      end
    end

    # ⚠️ Deliberately NOT ActiveRecord::Tasks::DatabaseTasks: its `create` re-establishes
    # ActiveRecord::Base's connection on the throwaway database and would hijack the suite.
    # Bare PG for the database lifecycle, `psql` for the load — the same binary `db:prepare`
    # uses (`structure_load` shells out to it), so this is the entrypoint's own path.
    it "round-trips #{name}_structure.sql into a fresh database (#{table} present)" do
      base = ActiveRecord::Base.connection_db_config.configuration_hash
      tmp = "#{base[:database]}_#{name}_rt_#{Process.pid}"
      pg = { host: base[:host], port: base[:port], user: base[:username], password: base[:password] }
      admin = PG.connect(pg.merge(dbname: "postgres"))
      begin
        admin.exec("CREATE DATABASE #{admin.quote_ident(tmp)}")
        env = { "PGHOST" => pg[:host].to_s, "PGPORT" => pg[:port].to_s, "PGUSER" => pg[:user].to_s,
                "PGPASSWORD" => pg[:password].to_s, "ON_ERROR_STOP" => "1" }
        loaded = system(env, "psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", tmp,
                        "-f", Rails.root.join("db/#{name}_structure.sql").to_s, out: File::NULL)
        expect(loaded).to be(true), "psql could not load db/#{name}_structure.sql (is `psql` on PATH?)"
        conn = PG.connect(pg.merge(dbname: tmp))
        tables = conn.exec("SELECT tablename FROM pg_tables WHERE schemaname = 'public'").map { |r| r["tablename"] }
        conn.close
        expect(tables).to include(table)
      ensure
        admin.exec("DROP DATABASE IF EXISTS #{admin.quote_ident(tmp)}")
        admin.close
      end
    end
  end
end
