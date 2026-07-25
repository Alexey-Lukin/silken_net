# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "yaml"
require_relative "../../scripts/sbom_conda_lock"

# [BIZ.24] Unit coverage for the conda-lock → CycloneDX translator. Pure
# functions + tmpdir lock fixtures (no Rails/DB); the same module the CLI wraps.
#
# The weight is on two places that can be silently WRONG rather than loud:
# (1) the build string, which is derived from the artefact filename and must
# survive package names that themselves contain `-`; and (2) the dedup, where a
# noarch artefact listed once per target platform must collapse to ONE component
# while a platform-specific build must NOT.
RSpec.describe SbomCondaLock do
  # A conda-lock v1 row, shaped exactly like the real file.
  def row(name:, version:, subdir:, build:, platform:, ext: ".conda",
          channel: "conda-forge", sha: "s" * 64, md5: "m" * 32, manager: "conda",
          category: "main", optional: false)
    { "name" => name, "version" => version, "manager" => manager, "platform" => platform,
      "url" => "https://conda.anaconda.org/#{channel}/#{subdir}/#{name}-#{version}-#{build}#{ext}",
      "hash" => { "md5" => md5, "sha256" => sha },
      "category" => category, "optional" => optional }
  end

  # A noarch package as the lock really carries it: the SAME file, once per target.
  def noarch_pair
    [ row(name: "joblib", version: "1.5.3", subdir: "noarch", build: "pyhd8ed1ab_0", platform: "linux-64"),
      row(name: "joblib", version: "1.5.3", subdir: "noarch", build: "pyhd8ed1ab_0", platform: "osx-arm64") ]
  end

  def with_lock(lock, env: nil)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "conda-lock.yml"), lock.to_yaml)
      File.write(File.join(dir, "environment.yml"), env.to_yaml) if env
      yield File.join(dir, "conda-lock.yml")
    end
  end

  describe ".strip_archive_ext" do
    it "handles both archive formats conda-forge serves" do
      expect(described_class.strip_archive_ext("joblib-1.5.3-pyhd8ed1ab_0.conda")).to eq("joblib-1.5.3-pyhd8ed1ab_0")
      # The naive File.extname would leave a trailing `.tar` here.
      expect(described_class.strip_archive_ext("defusedxml-0.7.1-pyhd8ed1ab_0.tar.bz2"))
        .to eq("defusedxml-0.7.1-pyhd8ed1ab_0")
    end
  end

  describe ".url_parts" do
    it "reads channel/subdir/filename off the artefact url" do
      parts = described_class.url_parts("https://conda.anaconda.org/conda-forge/noarch/joblib-1.5.3-pyhd8ed1ab_0.conda")
      expect(parts).to eq(channel: "conda-forge", subdir: "noarch",
                          filename: "joblib-1.5.3-pyhd8ed1ab_0.conda")
    end
  end

  describe ".build_string" do
    it "survives a name that contains dashes" do
      # Splitting the filename on `-` would call the build `sans` here — the
      # reason the build is peeled off a KNOWN name-version prefix instead.
      pkg = row(name: "font-ttf-dejavu-sans-mono", version: "2.37", subdir: "noarch",
                build: "hab24e00_0", platform: "linux-64")
      expect(described_class.build_string(pkg)).to eq("hab24e00_0")
    end

    it "is nil when the filename does not match the declared name-version" do
      pkg = row(name: "x", version: "1", subdir: "noarch", build: "b", platform: "linux-64")
      pkg["url"] = "https://conda.anaconda.org/conda-forge/noarch/totally-other-1.0-b.conda"
      expect(described_class.build_string(pkg)).to be_nil
    end
  end

  describe ".conda_purl" do
    it "takes subdir from the ARTEFACT url, not from the lock's target platform" do
      # A noarch wheel has no `…/linux-64/…` artefact; minting that purl would
      # name a file that does not exist.
      pkg = row(name: "joblib", version: "1.5.3", subdir: "noarch",
                build: "pyhd8ed1ab_0", platform: "linux-64")
      expect(described_class.conda_purl(pkg))
        .to eq("pkg:conda/joblib@1.5.3?build=pyhd8ed1ab_0&channel=conda-forge&subdir=noarch")
    end

    it "keeps qualifiers in the purl-spec's sorted order and percent-encodes a local version" do
      pkg = row(name: "pytorch", version: "2.1.0+cu118", subdir: "linux-64",
                build: "py312_0", platform: "linux-64")
      purl = described_class.conda_purl(pkg)
      expect(purl).to start_with("pkg:conda/pytorch@2.1.0%2Bcu118?")
      expect(purl.split("?").last.split("&").map { |q| q.split("=").first }).to eq(%w[build channel subdir])
    end
  end

  describe ".purl (manager routing)" do
    it "routes a pip row to pkg:pypi with the spec's name normalisation" do
      pkg = { "name" => "Typing_Extensions", "version" => "4.12.2", "manager" => "pip",
              "url" => "https://files.pythonhosted.org/packages/aa/typing_extensions-4.12.2-py3-none-any.whl" }
      expect(described_class.purl(pkg)).to eq("pkg:pypi/typing-extensions@4.12.2")
    end

    it "routes a conda row to pkg:conda" do
      pkg = row(name: "openmm", version: "8.1.1", subdir: "osx-arm64", build: "py312_0",
                platform: "osx-arm64")
      expect(described_class.purl(pkg)).to start_with("pkg:conda/openmm@8.1.1?")
    end
  end

  describe ".hashes" do
    it "emits both digests, strongest first" do
      pkg = row(name: "x", version: "1", subdir: "noarch", build: "b", platform: "linux-64")
      expect(described_class.hashes(pkg)).to eq(
        [ { "alg" => "SHA-256", "content" => "s" * 64 }, { "alg" => "MD5", "content" => "m" * 32 } ]
      )
    end

    it "emits MD5 alone when that is all the lock carries, and [] when there is no hash" do
      pkg = row(name: "x", version: "1", subdir: "noarch", build: "b", platform: "linux-64")
      pkg["hash"] = { "md5" => "m" * 32 }
      expect(described_class.hashes(pkg)).to eq([ { "alg" => "MD5", "content" => "m" * 32 } ])
      expect(described_class.hashes({})).to eq([])
    end
  end

  describe ".component" do
    subject(:component) do
      described_class.component(
        row(name: "joblib", version: "1.5.3", subdir: "noarch", build: "pyhd8ed1ab_0",
            platform: "linux-64"), %w[osx-arm64 linux-64]
      )
    end

    it "maps optional onto the native CycloneDX scope, not a property" do
      expect(component["scope"]).to eq("required")
      opt = row(name: "x", version: "1", subdir: "noarch", build: "b",
                platform: "linux-64", optional: true)
      expect(described_class.component(opt, [ "linux-64" ])["scope"]).to eq("optional")
      expect(described_class.component(opt, [ "linux-64" ])["properties"].map { |p| p["name"] })
        .not_to include("conda-lock:optional")
    end

    it "carries one sorted platform property per target plus the lock category" do
      expect(component["properties"]).to eq(
        [ { "name" => "conda-lock:platform", "value" => "linux-64" },
          { "name" => "conda-lock:platform", "value" => "osx-arm64" },
          { "name" => "conda-lock:category", "value" => "main" } ]
      )
    end

    it "records the artefact url as a distribution reference and mirrors purl into bom-ref" do
      expect(component["externalReferences"])
        .to eq([ { "type" => "distribution",
                   "url" => "https://conda.anaconda.org/conda-forge/noarch/joblib-1.5.3-pyhd8ed1ab_0.conda" } ])
      expect(component["bom-ref"]).to eq(component["purl"])
    end
  end

  describe ".build_components (the DEDUP decision)" do
    it "collapses a noarch artefact listed once per platform into ONE component" do
      components, problems = described_class.build_components(noarch_pair)
      expect(problems).to be_empty
      expect(components.size).to eq(1)
      expect(components.first["properties"].select { |p| p["name"] == "conda-lock:platform" }.map { |p| p["value"] })
        .to eq(%w[linux-64 osx-arm64])
    end

    it "keeps platform-SPECIFIC builds apart — their purls differ by subdir" do
      rows = [ row(name: "openmm", version: "8.1.1", subdir: "linux-64", build: "py312_0", platform: "linux-64"),
               row(name: "openmm", version: "8.1.1", subdir: "osx-arm64", build: "py312_0", platform: "osx-arm64") ]
      components, problems = described_class.build_components(rows)
      expect(problems).to be_empty
      expect(components.map { |c| c["purl"] }.uniq.size).to eq(2)
    end

    it "REPORTS a purl collision instead of merging two different files" do
      # The 1:1 purl↔artefact property this dedup rests on would break if
      # conda-forge ever served one build string in two archive formats.
      rows = [ row(name: "x", version: "1", subdir: "noarch", build: "b", platform: "linux-64"),
               row(name: "x", version: "1", subdir: "noarch", build: "b", platform: "linux-64",
                   ext: ".tar.bz2", sha: "z" * 64) ]
      components, problems = described_class.build_components(rows)
      expect(components.size).to eq(1)
      expect(problems).to include(a_string_matching(/purl collision.*x-1-b\.conda vs x-1-b\.tar\.bz2/))
    end

    it "flags a row that cannot be translated at all" do
      _components, problems = described_class.build_components([ { "name" => "x", "manager" => "conda" } ])
      expect(problems).to include(a_string_matching(/unusable lock row.*needs name\+version\+url/))
    end
  end

  describe ".audit — fixture lock" do
    let(:lock) do
      { "version" => 1,
        "metadata" => { "content_hash" => { "linux-64" => "c" * 64 },
                        "platforms" => %w[linux-64 osx-arm64], "sources" => [ "environment.yml" ] },
        "package" => noarch_pair + [ row(name: "openmm", version: "8.1.1", subdir: "linux-64",
                                         build: "py312_0", platform: "linux-64") ] }
    end

    it "emits a CycloneDX 1.6 fragment named after the env, with the lock's content_hash" do
      with_lock(lock, env: { "name" => "silken_md" }) do |path|
        bom = described_class.audit(lockfile: path)[:bom]
        expect(bom).to include("bomFormat" => "CycloneDX", "specVersion" => "1.6", "version" => 1)
        expect(bom["metadata"]["component"]).to include("name" => "silken_md",
                                                        "bom-ref" => "conda-env:silken_md")
        expect(bom["metadata"]["component"]["properties"])
          .to eq([ { "name" => "conda-lock:content_hash:linux-64", "value" => "c" * 64 } ])
        expect(bom).not_to have_key("serialNumber") # fragment — the aggregator mints one
      end
    end

    it "falls back to the lock's directory name when environment.yml is unreachable" do
      with_lock(lock) do |path| # no environment.yml written
        name = described_class.audit(lockfile: path)[:bom]["metadata"]["component"]["name"]
        expect(name).to eq(File.basename(File.dirname(path)))
      end
    end

    it "--platform narrows to that target's rows only" do
      with_lock(lock, env: { "name" => "silken_md" }) do |path|
        osx = described_class.audit(lockfile: path, platform: "osx-arm64")
        expect(osx[:rows].size).to eq(1)
        expect(osx[:components].map { |c| c["name"] }).to eq([ "joblib" ])
        expect(described_class.audit(lockfile: path)[:components].size).to eq(2) # joblib + openmm
      end
    end
  end

  describe ".audit — the real lock (regression guard)" do
    subject(:result) { described_class.audit }

    it "translates every row with no collision" do
      expect(result[:problems]).to be_empty
      expect(result[:components]).not_to be_empty
    end

    it "actually dedups: fewer components than lock rows, every bom-ref unique" do
      refs = result[:components].map { |c| c["bom-ref"] }
      expect(result[:components].size).to be < result[:rows].size
      expect(refs.uniq.size).to eq(refs.size)
    end

    it "gives every component a purl, a version and a SHA-256" do
      expect(result[:components].map { |c| c["purl"] }).to all(start_with("pkg:"))
      expect(result[:components].map { |c| c["version"] }).to all(be_a(String))
      expect(result[:components]).to all(
        include("hashes" => a_collection_including(hash_including("alg" => "SHA-256")))
      )
    end

    it "resolves the in-silico env name from environment.yml" do
      expect(result[:bom]["metadata"]["component"]["name"]).to eq("silken_md")
    end
  end
end
