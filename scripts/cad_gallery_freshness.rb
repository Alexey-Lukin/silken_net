#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# CAD-gallery freshness — the LOCAL carrier of the `DrawingTests` gallery pin [OPS.42].
#
# Every committed sheet `docs/images/cad/*.drawing.svg` names, in its footer, the manifest it
# was drawn from («SSOT cem/<file>») and that manifest's SHA-256 («sha256sum of the SSOT
# manifest file): <hex>»). The pin in `tools/cad/tests/SilkenCad.Tests/DrawingTests.cs`
# compares the pair — but only in CI: `.githooks/pre-push` does not run dotnet, so a CEM note
# edited without a re-render left `main` red on 2026-10-03 and was caught twice more on
# 2026-10-04 by a hand-run `dotnet test`, never by a hook. This asks the same question
# without dotnet.
#
# 🔑 It reads the COMMIT, never the working tree (`git cat-file blob <rev>:<path>`, rev =
# HEAD by default). Pre-push judges what is being pushed, and «re-rendered the sheet, forgot
# to `git add` it» is green on disk and red in CI — the working-tree form would bless exactly
# that (guard-craft #157).
#
# ⛔ Declared ceiling — the pin's own, deliberately not wider: it proves MANIFEST IDENTITY.
# A layout change in `Drawing.cs` that leaves every manifest alone reds nothing here, and the
# PNG renders beside the sheets are checked by nothing at all. The sheet population is the
# directory listing (`*.drawing.svg` at the commit), not the pin's InlineData roster, so a
# NEW sheet is covered the day it is committed, while the pin covers it only once someone
# adds a row.
# 🔴 The weakest link the ⚖️ named — «a sheet whose footer carries no hash would pass
# silently» — is closed by refusal, not by trust: a sheet without exactly one manifest name
# and one hash is RED (that includes the `NOT COMPUTED (no CEM file)` marker of an in-memory
# CEM, which has no business in the gallery). The label literal below mirrors
# `Drawing.CemIdentityLine`: renaming it there reds every sheet LOUDLY (no hash found), never
# silently — keep the two in step.
#
# Usage:
#   ruby scripts/cad_gallery_freshness.rb [--rev REV]   exit 0 fresh · 1 stale or unreadable sheet ·
#                                                       2 NOT RUN (git could not read the commit)
#   ruby scripts/cad_gallery_freshness.rb --selftest    the RED branches have no witness in a fresh
#                                                       gallery, so they carry their own battery

require "digest"
require "open3"

module CadGalleryFreshness
  GALLERY    = "docs/images/cad"
  CEM_DIR    = "tools/cad/cem"
  HASH_LABEL = "sha256sum of the SSOT manifest file): "
  NAME_RE    = %r{· SSOT cem/([^<\s]+\.json)<}
  HASH_RE    = /#{Regexp.escape(HASH_LABEL)}([0-9a-f]{64})(?![0-9a-f])/
  RECIPE     = "re-draw it: (cd tools/cad && dotnet run --project src/SilkenCad -- draw cem/<file>), " \
               "copy out/<name>.drawing.svg into #{GALLERY}/ — or run the drawing loops of " \
               "tools/cad/scripts/render_gallery.sh — then COMMIT the sheet"

  module_function

  # sheets: { "x.drawing.svg" => svg text } · manifest: ->(file) { bytes, or nil if absent }
  def judge(sheets, manifest)
    return [ "no *.drawing.svg in #{GALLERY} at this commit — a check over an empty set is green by construction" ] if sheets.empty?

    sheets.sort.filter_map do |sheet, svg|
      names  = svg.scan(NAME_RE).flatten.uniq
      hashes = svg.scan(HASH_RE).flatten.uniq
      if names.size != 1 || hashes.size != 1
        "#{sheet}: footer names #{names.size} manifest(s) and #{hashes.size} SHA-256(s), expected one of each — " \
          "a sheet that does not say what it was drawn from cannot be judged, so it is refused; #{RECIPE}"
      elsif (bytes = manifest.call(names[0])).nil?
        "#{sheet}: names cem/#{names[0]}, which this commit does not ship"
      elsif (live = Digest::SHA256.hexdigest(bytes)) != hashes[0]
        "#{sheet}: drawn from cem/#{names[0]} @ #{hashes[0][0, 12]}…, this commit ships #{live[0, 12]}… — #{RECIPE}"
      end
    end
  end

  def git(*args)
    out, status = Open3.capture2("git", *args, binmode: true)
    status.success? ? out : nil
  end

  def run(rev)
    listing = git("ls-tree", "-r", "--name-only", rev, "--", GALLERY)
    return warn("cad_gallery_freshness: NOT RUN — git cannot list #{GALLERY} at #{rev}; this is not a verdict") || 2 if listing.nil?

    sheets = listing.split("\n").grep(/\.drawing\.svg\z/).to_h do |path|
      [ File.basename(path), git("cat-file", "blob", "#{rev}:#{path}").to_s.force_encoding(Encoding::UTF_8) ]
    end
    errors = judge(sheets, ->(file) { git("cat-file", "blob", "#{rev}:#{CEM_DIR}/#{file}") })
    if errors.empty?
      puts "cad_gallery_freshness: #{sheets.size} sheet(s) at #{rev} name the manifest bytes this commit ships ✓"
      return 0
    end
    errors.each { |e| warn "  ✗ #{e}" }
    warn "cad_gallery_freshness: #{errors.size} of #{sheets.size} sheet(s) stale or unreadable at #{rev}"
    1
  end

  def selftest
    foot  = ->(file) { "<text>SilkenNet · CEM-native drawing · rev x · SSOT cem/#{file}</text>" }
    good  = ->(file, hex) { foot.(file) + "<text>CEM SHA-256 (#{HASH_LABEL}#{hex}</text>" }
    bytes = "{\"kind\":\"ti_coin\"}\n"
    hex   = Digest::SHA256.hexdigest(bytes)
    shelf = ->(file) { file == "a.json" ? bytes : nil }
    name_only = foot.("a.json")
    cases = [
      [ "fresh sheet passes",                 { "a.drawing.svg" => good.("a.json", hex) },                                  0 ],
      [ "stale hash is RED",                  { "a.drawing.svg" => good.("a.json", "0" * 64) },                             1 ],
      [ "no hash line is RED, not skipped",   { "a.drawing.svg" => name_only },                                             1 ],
      [ "NOT COMPUTED marker is RED",         { "a.drawing.svg" => name_only + "<text>CEM SHA-256 (#{HASH_LABEL}NOT COMPUTED (no CEM file)</text>" }, 1 ],
      [ "no manifest name is RED",            { "a.drawing.svg" => "<text>CEM SHA-256 (#{HASH_LABEL}#{hex}</text>" },       1 ],
      [ "two manifest names are RED",         { "a.drawing.svg" => good.("a.json", hex) + foot.("b.json") }, 1 ],
      [ "a manifest the commit lacks is RED", { "a.drawing.svg" => good.("b.json", hex) },                                  1 ],
      [ "empty gallery is RED",               {},                                                                            1 ],
      [ "one stale among fresh names IT",     { "a.drawing.svg" => good.("a.json", hex), "z.drawing.svg" => good.("a.json", "f" * 64) }, 1 ]
    ]
    fails = cases.count do |name, sheets, expect|
      got = judge(sheets, shelf)
      ok  = got.size == expect && (expect.zero? || name != "one stale among fresh names IT" || got.first.start_with?("z.drawing.svg"))
      puts format("  %s %-36s %s", ok ? "✓" : "✗", name, ok ? "#{got.size} error(s)" : "expected #{expect}, got #{got.inspect}")
      !ok
    end
    puts "cad_gallery_freshness --selftest: #{fails.zero? ? 'OK' : "#{fails} FAILED"} (#{cases.size} cases)"
    fails.zero? ? 0 : 1
  end
end

if $PROGRAM_NAME == __FILE__
  exit CadGalleryFreshness.selftest if ARGV.include?("--selftest")
  rev = (i = ARGV.index("--rev")) ? ARGV[i + 1] : "HEAD"
  exit CadGalleryFreshness.run(rev)
end
