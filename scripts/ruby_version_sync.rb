#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Ruby-version parity gate (OPS.13).
#
# The Ruby version lives in EIGHT mirrors with (until 2026-07-16) no gate on
# their parity — and Dependabot's `docker` ecosystem bumps ONLY the Dockerfile
# FROM-tag: the image then carries the new Ruby while the Gemfile hard-pin
# demands the old one, so `bundle install` dies INSIDE the image build. The PR
# stays green because no PR trigger builds the image (`mirror-ghcr.yml` fires
# from `main`) — the live trap was PR #463 (4.0.5-slim → 4.0.6-slim). The
# sibling half is the `docker_smoke` job in ci.yml (paths-gated full build,
# no push, part of the required `ci-ok` aggregate); THIS gate makes the
# version itself One-Home: `.ruby-version` = SSOT, everything else mirrors.
#
# Each mirror carries a curated regex set (the field_canon_sync tripwire
# style): a pattern that stops matching = dead mirror entry = RED, so the
# list cannot rot silently; a matched value ≠ SSOT = drift = RED.
#
# Pure Ruby (stdlib only). Run: ruby scripts/ruby_version_sync.rb
# Exit 0 = in sync; exit 1 = drift. Method/why → docs/00_06 §3.
# Require-safe: `guard_registry_sync.rb` imports MIRRORS to assert every
# mirror sits inside the docs.yml `changes` filter (anti-decorative, CHECK D).

module RubyVersionSync
  ROOT = File.expand_path("..", __dir__)
  SSOT = ".ruby-version"
  V    = /(\d+\.\d+\.\d+)/

  MIRRORS = {
    "Gemfile"                                    => [ /^ruby "#{V}"/ ],
    ".rvmrc"                                     => [ /\bruby-#{V}@/ ],
    "Dockerfile"                                 => [ %r{^FROM docker\.io/library/ruby:#{V}-} ],
    "CLAUDE.md"                                  => [ /Ruby #{V}/, /ruby --version\s+#\s*#{V}/ ],
    "AGENTS.md"                                  => [ /Ruby #{V}/ ],
    ".github/copilot-instructions.md"            => [ /Ruby #{V}/ ],
    "docs/06_01_Deployment_Kamal_Terraform.md"   => [ /ruby:#{V}-slim/ ]
  }.freeze

  module_function

  def ssot_version
    File.read(File.join(ROOT, SSOT))[V, 1]
  end

  def check
    want = ssot_version
    return [ "#{SSOT}: не можу розпарсити версію (очікую ruby-X.Y.Z)" ] unless want

    MIRRORS.flat_map do |file, patterns|
      text = File.read(File.join(ROOT, file))
      patterns.flat_map do |re|
        found = text.scan(re).flatten.compact
        if found.empty?
          [ "#{file}: дзеркало мертве — жоден рядок не матчить #{re.inspect} (онови MIRRORS разом із файлом)" ]
        else
          found.reject { |v| v == want }.map { |v| "#{file}: Ruby #{v} ≠ SSOT #{want} (#{SSOT})" }
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  errors = RubyVersionSync.check
  if errors.empty?
    puts "ruby_version_sync ✓ — Ruby #{RubyVersionSync.ssot_version} across " \
         "#{RubyVersionSync::MIRRORS.size + 1} дзеркал (SSOT #{RubyVersionSync::SSOT})"
    exit 0
  else
    warn "ruby_version_sync ✗ — Ruby-версія розійшлася по дзеркалах (OPS.13):"
    errors.each { |e| warn "  · #{e}" }
    warn "Повний Ruby-бамп = рецепт скіла dependency-update (усі дзеркала + rvm install + full bin/rspec)."
    exit 1
  end
end
