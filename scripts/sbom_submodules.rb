#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [BIZ.24] CycloneDX-1.6 SBOM fragment for GIT SUBMODULES — the dependency class
# that NO off-the-shelf scanner sees.
#
# The aggregated SBOM (EU CRA Annex I Part II · enterprise procurement) is built
# from Syft (Gemfile.lock, package-lock.json, requirements-*.txt, GH-Actions) +
# Trivy (conda `environment.yml`, NuGet Central-Package-Management) + `dotnet
# CycloneDX`. Verified empirically: NONE of them — nor GitHub's own
# dependency-graph SBOM — reports a single git submodule. Yet `firmware/extern/`
# is vendored THIRD-PARTY C that ships INSIDE the Soldier/Queen binary (mruby,
# CMSIS-DSP, Monocypher, the ST HAL + LoRaWAN middleware) and `tools/cad/extern/`
# is vendored C# compiled into the CAD tool. A submodule pin IS a dependency: it
# has an upstream, a version, and CVEs. Unlisted, the SBOM understates the
# firmware attack surface — precisely the thing CRA asks about. This closes it.
#
# WHY hand-rolled: `.gitmodules` + a gitlink is a two-field problem (`url`,
# 40-char commit). ~120 lines of stdlib beats adding a scanner that still would
# not resolve the pin to a purl.
#
# 🔴 THE NON-OBVIOUS PART — it must work WITHOUT the submodules checked out.
# CI clones without `--recurse-submodules` on purpose (an anti-noise filter: no
# vendored third-party tree in the scan surface). `git submodule status` still
# prints the pinned SHA for an uninitialised submodule, just prefixed `-` (also
# `+` = checked-out-but-drifted, `U` = merge conflict) — so the SHA is read from
# the SUPERPROJECT INDEX, never from a working tree. Fallback when status is
# unusable: `git ls-tree HEAD -- <path>` → the raw `160000 commit <sha>` gitlink.
#
# purl mapping (purl-spec type definitions):
#   github.com/<owner>/<repo>  → `pkg:github/<owner>/<repo>@<sha>` — the github
#     type takes a commit as version, and the spec mandates a LOWERCASED
#     namespace+name (so `LEAP71_ShapeKernel` → `leap71_shapekernel` in the purl
#     while `component.name` keeps upstream's casing — that asymmetry is correct,
#     not a bug).
#   any other host → `pkg:generic/<repo>?vcs_url=git%2B<https url>%40<sha>`,
#     percent-encoding only `+` and `@` (the form in the purl-spec test suite).
#
# KNOWN LIMITATION (honest, not a TODO): a RELATIVE submodule url (`url = ../x`,
# git resolves it against the superproject's remote) is NOT resolved — it falls
# through to the generic purl with the literal path. None exist in this repo; if
# one is added, the purl is ugly but never WRONG about a host it invented.
#
# Output is a FRAGMENT: no `serialNumber` (the aggregator mints one) and the
# `metadata.timestamp` honours `SOURCE_DATE_EPOCH`, so a committed fragment does
# not churn on every run. JSON goes to STDOUT (or `--output`); every human line
# goes to STDERR, so `ruby scripts/sbom_submodules.rb > sbom.json` is valid JSON.
#
# Pure Ruby (json/open3/time stdlib, no Rails). Run from repo root:
#   ruby scripts/sbom_submodules.rb                        # fragment → stdout
#   ruby scripts/sbom_submodules.rb --output sbom-sub.json
#   ruby scripts/sbom_submodules.rb --assert               # drift gate
# `--assert` exit 1 = a `.gitmodules` entry produced no component (unreadable
# url/path, or no pinned SHA anywhere) or two components collided on `bom-ref`
# (a duplicate ref makes the whole BOM schema-invalid). Exit 0 = fragment sound.

require "json"
require "open3"
require "time"

module SbomSubmodules
  ROOT = File.expand_path("..", __dir__)
  GITMODULES = ".gitmodules"

  # `[ |+|-|U]<40-hex> <path>[ (describe)]`. The flag is optional so a
  # hand-fed line without it still parses.
  STATUS_LINE = /\A[ +\-U]?(?<sha>[0-9a-f]{40})\s+(?<rest>\S.*)\z/
  GITLINK     = /^160000 commit (?<sha>[0-9a-f]{40})\t/
  GITHUB_REPO = %r{\Ahttps://github\.com/(?<owner>[^/]+)/(?<repo>[^/]+)\z}

  module_function

  # `.gitmodules` is plain git-config INI and the two keys we need are flat, so
  # parse it in Ruby rather than shelling out to `git config --file` — one less
  # subprocess and the fixtures in the spec need no git at all. Every
  # `[submodule "…"]` header is returned, even a malformed one: the count of
  # HEADERS is the denominator `--assert` measures against.
  def parse_gitmodules(text)
    entries = []
    text.to_s.each_line do |raw|
      line = raw.strip
      if (m = line.match(/\A\[submodule\s+"(?<name>[^"]*)"\]\z/))
        entries << { name: m[:name] }
      elsif !entries.empty? && (m = line.match(/\A(?<key>[A-Za-z][\w-]*)\s*=\s*(?<val>.*)\z/))
        entries.last[m[:key].downcase.to_sym] = m[:val].strip
      end
    end
    entries
  end

  # Any git-accepted remote form → a canonical `https://host/path` without the
  # trailing `.git`, so `git@github.com:o/r.git` and `https://github.com/o/r.git`
  # collapse to ONE identity. A relative/local path keeps its literal form — we
  # do not invent a host we cannot know.
  def normalize_vcs_url(raw)
    url = raw.to_s.strip
    return url if url.empty?

    if !url.include?("//") && (m = url.match(%r{\A(?:[^@/]+@)?(?<host>[^@:/]+):(?<path>[^/].*)\z}))
      url = "https://#{m[:host]}/#{m[:path]}"
    elsif (m = url.match(%r{\A(?:git|ssh|https?)://(?:[^@/]+@)?(?<rest>.+)\z}))
      url = "https://#{m[:rest]}"
    else
      return url # relative/local path — literal, untouched
    end
    url.delete_suffix("/").delete_suffix(".git")
  end

  # [owner, repo] for a github.com repo ROOT, else nil (→ generic purl).
  def github_slug(url)
    m = GITHUB_REPO.match(url.to_s)
    m && [ m[:owner], m[:repo] ]
  end

  # Last path segment — the repo name for a non-github host.
  def repo_name(url)
    url.to_s.delete_suffix("/").split("/").last.to_s.delete_suffix(".git")
  end

  # Only `+` and `@` are encoded — the shape purl-spec's own test suite uses for
  # `vcs_url` (`:` and `/` stay literal, which keeps the url readable).
  def pct(str)
    str.gsub("+", "%2B").gsub("@", "%40")
  end

  def purl(url, sha)
    if (slug = github_slug(url))
      "pkg:github/#{slug[0].downcase}/#{slug[1].downcase}@#{sha}"
    else
      "pkg:generic/#{repo_name(url)}?vcs_url=#{pct("git+#{url}@#{sha}")}"
    end
  end

  def component(url:, sha:)
    normalized = normalize_vcs_url(url)
    slug = github_slug(normalized)
    ref  = purl(normalized, sha)
    {
      "type"    => "library",
      "bom-ref" => ref,
      "group"   => slug&.first,
      "name"    => slug ? slug.last : repo_name(normalized),
      "version" => sha,
      "purl"    => ref,
      "externalReferences" => [ { "type" => "vcs", "url" => normalized } ]
    }.compact
  end

  def parse_status(out)
    out.to_s.lines.filter_map do |line|
      next unless (m = STATUS_LINE.match(line.chomp))

      # The trailing ` (v1.2.3)` describe-suffix is decoration; the path is the rest.
      [ m[:rest].sub(/\s+\([^()]*\)\z/, "").strip, m[:sha] ]
    end.to_h
  end

  def git(root, *args)
    out, _err, st = Open3.capture3("git", "-C", root, *args)
    st.success? ? out : nil
  rescue Errno::ENOENT
    nil
  end

  # Superproject-index gitlink for one path — the fallback when `git submodule
  # status` is unusable (bare/odd checkout).
  def sha_from_tree(root, path)
    m = GITLINK.match(git(root, "ls-tree", "HEAD", "--", path).to_s)
    m && m[:sha]
  end

  # { path => 40-char sha }; status first (works uninitialised), ls-tree per miss.
  def pinned_shas(root:, paths:)
    from_status = parse_status(git(root, "submodule", "status"))
    paths.to_h { |p| [ p, from_status[p] || sha_from_tree(root, p) ] }.compact
  end

  # ISO-8601 UTC; `SOURCE_DATE_EPOCH` (reproducible-builds convention) pins it.
  def timestamp
    now = (e = ENV["SOURCE_DATE_EPOCH"]) ? Time.at(Integer(e, 10)) : Time.now
    now.getutc.strftime("%Y-%m-%dT%H:%M:%SZ")
  end

  # `metadata.component` = this repository itself, pinned to its own HEAD.
  def self_component(root:)
    url  = normalize_vcs_url(git(root, "remote", "get-url", "origin").to_s.strip)
    head = git(root, "rev-parse", "HEAD").to_s.strip
    head = nil unless head.match?(/\A[0-9a-f]{40}\z/)
    slug = github_slug(url)
    ref  = (head && !url.empty?) ? purl(url, head) : nil
    {
      "type"    => "application",
      "bom-ref" => ref,
      "group"   => slug&.first,
      "name"    => (slug ? slug.last : (url.empty? ? File.basename(root) : repo_name(url))),
      "version" => head,
      "purl"    => ref,
      "externalReferences" => (url.empty? ? nil : [ { "type" => "vcs", "url" => url } ])
    }.compact
  end

  # Returns { bom:, entries:, components:, problems: }. `problems` is what
  # `--assert` gates on — every `.gitmodules` header must yield one component.
  def audit(root: ROOT)
    entries = parse_gitmodules(File.read(File.join(root, GITMODULES)))
    usable  = entries.select { |e| e[:path] && e[:url] }
    shas    = pinned_shas(root:, paths: usable.map { |e| e[:path] })

    problems = []
    components = usable.filter_map do |e|
      if (sha = shas[e[:path]])
        component(url: e[:url], sha:)
      else
        problems << "`#{e[:name]}` (#{e[:path]}) — no pinned SHA: neither " \
                    "`git submodule status` nor `git ls-tree HEAD` returned a gitlink"
        nil
      end
    end

    (entries - usable).each do |e|
      problems << "`#{e[:name]}` — incomplete .gitmodules entry " \
                  "(path=#{e[:path].inspect} url=#{e[:url].inspect})"
    end

    dupes = components.group_by { |c| c["bom-ref"] }.select { |_r, v| v.size > 1 }.keys
    dupes.each do |ref|
      problems << "duplicate bom-ref `#{ref}` — two submodules pin the same " \
                  "repo+commit; a repeated bom-ref makes the BOM schema-invalid"
    end

    bom = {
      "bomFormat"   => "CycloneDX",
      "specVersion" => "1.6",
      "version"     => 1,
      "metadata"    => {
        "timestamp" => timestamp,
        "tools"     => { "components" => [ { "type" => "application",
                                             "name" => "scripts/sbom_submodules.rb" } ] },
        "component" => self_component(root:)
      },
      "components"  => components
    }
    { bom:, entries:, components:, problems: }
  end
end

if __FILE__ == $PROGRAM_NAME
  out_path = (i = ARGV.index("--output")) ? ARGV[i + 1] : nil
  result   = SbomSubmodules.audit
  json     = JSON.pretty_generate(result[:bom])

  if out_path
    File.write(out_path, "#{json}\n")
  else
    puts json
  end

  warn "sbom_submodules — #{result[:components].size} component(s) from " \
       "#{result[:entries].size} .gitmodules entr#{result[:entries].size == 1 ? 'y' : 'ies'}" \
       "#{out_path ? " → #{out_path}" : ''}"

  if ARGV.include?("--assert")
    if result[:problems].empty?
      warn "sbom_submodules ✓ — every submodule pin resolved to a CycloneDX component (BIZ.24)."
      exit 0
    end
    warn "sbom_submodules ✗ — submodule SBOM drift (BIZ.24):"
    result[:problems].each { |p| warn "  · #{p}" }
    exit 1
  end
end
