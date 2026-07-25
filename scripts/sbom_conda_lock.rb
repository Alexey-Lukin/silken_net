#!/usr/bin/env ruby
# frozen_string_literal: true

# [BIZ.24] CycloneDX-1.6 SBOM fragment from `tools/in_silico/conda-lock.yml` —
# the VERSION-PINNED in-silico environment, which no tool in the chain can read.
#
# The aggregated SBOM gets Ruby/JS/pip/Actions from Syft and NuGet from Trivy +
# `dotnet CycloneDX`. For conda, Trivy reads only the SOURCE manifest
# `environment.yml` — i.e. package NAMES with no versions (`openmm>=8.1`), which
# is useless for vulnerability matching. The RESOLVED artefact list lives in
# `conda-lock.yml`, and NOTHING reads it: `cyclonedx-python` dropped conda
# support in v4, Syft has no conda-lock parser. So the in-silico half of the
# platform — the DFT/MD stack behind every published EBFC number (01_03) — would
# appear in the SBOM as unversioned wishes. This translates the lock instead.
#
# Read the lock, do not assume it: a conda-lock v1 `package:` row carries
# `name`/`version`/`manager`/`platform`/`dependencies`/`url`/`hash`/`category`/
# `optional` — and NO `build` key. The build string and the channel are therefore
# derived from the artefact URL
# (`…/<channel>/<subdir>/<name>-<version>-<build>.conda`), taking the build as
# what remains after the known `name-version-` prefix and the archive extension
# (`.conda` or `.tar.bz2`) — safe for the many names that themselves contain `-`.
#
# 🔴 DEDUP DECISION — one component per ARTEFACT, keyed on purl; the lock's target
# platforms ride in `properties`. WHY:
#   · A lock row is (artefact × target platform), so an ARCH-INDEPENDENT package
#     (`…/noarch/…`) appears once per platform while being literally the SAME FILE
#     — same url, same sha256. Emitting it twice would double-count its CVEs and
#     force a synthetic `bom-ref` suffix (a repeated `bom-ref` is schema-invalid,
#     and two components with an identical `purl` is worse: it lies about the
#     artefact count).
#   · Nothing is lost by grouping: a platform-SPECIFIC build differs in `subdir`
#     AND usually in `build`, so its purl differs and it stays a separate
#     component. Only genuinely identical files collapse.
#   · The purl is a true artefact identity here — verified on this lock: the
#     count of distinct (name, version, build, channel, subdir) tuples equals the
#     count of distinct urls, 1:1. Should conda-forge ever repackage the same
#     build string into a second archive format, that 1:1 breaks — so the script
#     REPORTS such a collision instead of silently merging two files into one
#     component (and `--assert` fails on it).
# `optional` maps onto the native CycloneDX `scope` (`required`/`optional`)
# rather than a property — the field already exists; `category` (conda-lock's
# main/dev split) has no native home, so it stays a property.
#
# Output is a FRAGMENT: no `serialNumber` (the aggregator mints one) and
# `metadata.timestamp` honours `SOURCE_DATE_EPOCH`, so a committed fragment does
# not churn on every run. JSON goes to STDOUT (or `--output`); every human line
# goes to STDERR, so `ruby scripts/sbom_conda_lock.rb > sbom.json` is valid JSON.
#
# Pure Ruby (yaml/json/time stdlib, no Rails). Run from repo root:
#   ruby scripts/sbom_conda_lock.rb                          # fragment → stdout
#   ruby scripts/sbom_conda_lock.rb --output sbom-conda.json
#   ruby scripts/sbom_conda_lock.rb --platform linux-64      # single platform
#   ruby scripts/sbom_conda_lock.rb --assert                 # sanity gate
# `--assert` exit 1 = a row could not be translated (missing name/version/url) or
# two distinct artefacts collided on one purl. Exit 0 = fragment sound.

require "yaml"
require "json"
require "time"

module SbomCondaLock
  ROOT     = File.expand_path("..", __dir__)
  LOCKFILE = "tools/in_silico/conda-lock.yml"
  ARCHIVE_EXT = [ ".conda", ".tar.bz2", ".tar.gz" ].freeze

  # conda-lock hash keys → CycloneDX 1.6 `hashes[].alg`, strongest first.
  HASH_ALGS = { "sha512" => "SHA-512", "sha256" => "SHA-256",
                "sha1" => "SHA-1", "md5" => "MD5" }.freeze

  module_function

  def lock_path(root, lockfile)
    File.absolute_path?(lockfile) ? lockfile : File.join(root, lockfile)
  end

  def load_lock(path)
    YAML.safe_load_file(path, aliases: true) || {}
  end

  def strip_archive_ext(filename)
    ARCHIVE_EXT.each { |ext| return filename.delete_suffix(ext) if filename.end_with?(ext) }
    File.basename(filename, File.extname(filename))
  end

  # `…/<channel>/<subdir>/<file>` — the last three url segments. Returns
  # { channel:, subdir:, filename: }; any missing segment is nil (a pip wheel url
  # has no such layout, and that branch never asks for these).
  def url_parts(url)
    seg = url.to_s.split("?").first.to_s.split("/")
    { filename: seg[-1], subdir: seg[-2], channel: seg[-3] }
  end

  # The build string = what is left of the filename after the known
  # `name-version-` prefix and the archive extension. Deriving it this way (not
  # by splitting on `-`) is what makes `argon2-cffi-bindings` and
  # `font-ttf-dejavu-sans-mono` parse correctly.
  def build_string(pkg)
    base = strip_archive_ext(url_parts(pkg["url"])[:filename].to_s)
    stem = "#{pkg['name']}-#{pkg['version']}-"
    base.start_with?(stem) ? base.delete_prefix(stem) : nil
  end

  # purl qualifiers must be sorted by key — build < channel < subdir already is.
  # `subdir` is the artefact's REAL subdir from the url (so `noarch` stays
  # `noarch`), NOT the lock's target platform: the platform is a consumer of the
  # artefact, not a property of it, and conflating them would mint purls for
  # files that do not exist (`…/linux-64/joblib-…` for a noarch wheel).
  def conda_purl(pkg)
    parts = url_parts(pkg["url"])
    quals = { "build" => build_string(pkg), "channel" => parts[:channel],
              "subdir" => parts[:subdir] }.compact
    qs = quals.map { |k, v| "#{k}=#{pct(v)}" }.join("&")
    "pkg:conda/#{pct(pkg['name'])}@#{pct(pkg['version'].to_s)}#{qs.empty? ? '' : "?#{qs}"}"
  end

  # purl-spec pypi definition: the name is lowercased and `_` becomes `-`.
  def pypi_purl(pkg)
    "pkg:pypi/#{pct(pkg['name'].to_s.downcase.tr('_', '-'))}@#{pct(pkg['version'].to_s)}"
  end

  def purl(pkg)
    pkg["manager"].to_s == "pip" ? pypi_purl(pkg) : conda_purl(pkg)
  end

  # Minimal percent-encoding for the purl-reserved characters that can appear in
  # a conda version/build (`!` epoch, `+` local version, spaces).
  def pct(str)
    str.to_s.gsub(/[^A-Za-z0-9._~\-\/]/) { |c| format("%%%02X", c.ord) }
  end

  def hashes(pkg)
    h = pkg["hash"]
    return [] unless h.is_a?(Hash)

    HASH_ALGS.filter_map do |key, alg|
      content = h[key]
      { "alg" => alg, "content" => content } if content.is_a?(String) && !content.empty?
    end
  end

  # One CycloneDX component per artefact. `platforms` = every lock target that
  # resolved to this exact file (see the DEDUP DECISION above).
  def component(pkg, platforms)
    ref = purl(pkg)
    props = platforms.compact.sort.map { |p| { "name" => "conda-lock:platform", "value" => p } }
    props << { "name" => "conda-lock:category", "value" => pkg["category"] } if pkg["category"]
    {
      "type"    => "library",
      "bom-ref" => ref,
      "name"    => pkg["name"],
      "version" => pkg["version"].to_s,
      "purl"    => ref,
      "scope"   => (pkg["optional"] ? "optional" : "required"),
      "hashes"  => hashes(pkg),
      "externalReferences" => (pkg["url"] ? [ { "type" => "distribution", "url" => pkg["url"] } ] : nil),
      "properties" => (props.empty? ? nil : props)
    }.compact.reject { |_k, v| v == [] }
  end

  # ISO-8601 UTC; `SOURCE_DATE_EPOCH` (reproducible-builds convention) pins it.
  def timestamp
    now = (e = ENV["SOURCE_DATE_EPOCH"]) ? Time.at(Integer(e, 10)) : Time.now
    now.getutc.strftime("%Y-%m-%dT%H:%M:%SZ")
  end

  # `metadata.component` = the conda ENV the lock resolves, carrying the lock's
  # own per-platform `content_hash` so the fragment is traceable to the exact lock.
  def self_component(lock, env_name)
    ch = lock.dig("metadata", "content_hash")
    props = (ch.is_a?(Hash) ? ch : {}).sort.map do |plat, hash|
      { "name" => "conda-lock:content_hash:#{plat}", "value" => hash.to_s }
    end
    { "type" => "application", "bom-ref" => "conda-env:#{env_name}", "name" => env_name,
      "properties" => (props.empty? ? nil : props) }.compact
  end

  # Group the lock rows into artefacts. Returns [components, problems].
  def build_components(rows)
    problems = []
    groups   = {}

    rows.each do |pkg|
      unless pkg.is_a?(Hash) && pkg["name"] && pkg["version"] && pkg["url"]
        problems << "unusable lock row #{pkg.inspect[0, 120]} — needs name+version+url"
        next
      end

      ref = purl(pkg)
      if (seen = groups[ref]) && seen[:pkg]["url"] != pkg["url"]
        problems << "purl collision `#{ref}` — two DIFFERENT artefacts " \
                    "(#{File.basename(seen[:pkg]['url'])} vs #{File.basename(pkg['url'])}); " \
                    "grouping would merge two files into one component"
        next
      end
      groups[ref] ||= { pkg:, platforms: [] }
      groups[ref][:platforms] |= [ pkg["platform"] ]
    end

    [ groups.map { |_ref, g| component(g[:pkg], g[:platforms]) }, problems ]
  end

  # Returns { bom:, rows:, components:, problems:, platforms: }.
  def audit(root: ROOT, lockfile: LOCKFILE, platform: nil)
    path = lock_path(root, lockfile)
    lock = load_lock(path)
    rows = Array(lock["package"])
    rows = rows.select { |p| p.is_a?(Hash) && p["platform"] == platform } if platform

    components, problems = build_components(rows)
    env_name = conda_env_name(path, lock)

    bom = {
      "bomFormat"   => "CycloneDX",
      "specVersion" => "1.6",
      "version"     => 1,
      "metadata"    => {
        "timestamp" => timestamp,
        "tools"     => { "components" => [ { "type" => "application",
                                             "name" => "scripts/sbom_conda_lock.rb" } ] },
        "component" => self_component(lock, env_name)
      },
      "components"  => components
    }
    { bom:, rows:, components:, problems:,
      platforms: Array(lock.dig("metadata", "platforms")) }
  end

  # The env name is not in the lock — it lives in the `environment.yml` the lock
  # was solved from (`metadata.sources`). Read it if reachable, else fall back to
  # the lock's directory name rather than inventing one.
  def conda_env_name(lock_path, lock)
    dir = File.dirname(lock_path)
    src = Array(lock.dig("metadata", "sources")).find { |s| s.to_s.end_with?(".yml", ".yaml") }
    file = src && File.join(dir, src)
    name = (YAML.safe_load_file(file) || {})["name"] if file && File.file?(file)
    name || File.basename(dir)
  end
end

if __FILE__ == $PROGRAM_NAME
  out_path = (i = ARGV.index("--output")) ? ARGV[i + 1] : nil
  platform = (i = ARGV.index("--platform")) ? ARGV[i + 1] : nil
  result   = SbomCondaLock.audit(platform:)
  json     = JSON.pretty_generate(result[:bom])

  if out_path
    File.write(out_path, "#{json}\n")
  else
    puts json
  end

  warn "sbom_conda_lock — #{result[:components].size} component(s) from " \
       "#{result[:rows].size} lock row(s) " \
       "[#{platform || result[:platforms].join(', ')}]#{out_path ? " → #{out_path}" : ''}"

  if ARGV.include?("--assert")
    if result[:problems].empty?
      warn "sbom_conda_lock ✓ — every lock row translated, no purl collision (BIZ.24)."
      exit 0
    end
    warn "sbom_conda_lock ✗ — conda-lock SBOM drift (BIZ.24):"
    result[:problems].each { |p| warn "  · #{p}" }
    exit 1
  end
end
