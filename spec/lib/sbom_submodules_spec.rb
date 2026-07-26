# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "open3"
require_relative "../../scripts/sbom_submodules"

# [BIZ.24] Unit coverage for the git-submodule SBOM fragment generator. Pure
# functions + fixture-repo audits (no Rails/DB); the same module the CLI wraps.
#
# The fixture repos fabricate gitlinks with `git update-index --cacheinfo
# 160000,<sha>,<path>` instead of cloning a real submodule. That is not a
# shortcut — it produces EXACTLY the shape CI has (a pinned SHA in the
# superproject index with no working tree), which is the load-bearing claim of
# the script: the pin is read from the index, never from a checkout.
RSpec.describe SbomSubmodules do
  let(:sha_a) { "a1" * 20 }
  let(:sha_b) { "b2" * 20 }

  def git!(root, *args)
    out, err, st = Open3.capture3("git", "-C", root, *args)
    raise "git #{args.join(' ')} failed: #{err}#{out}" unless st.success?
  end

  # Throwaway repo: `.gitmodules` text + { path => sha } fabricated gitlinks.
  def with_fixture_repo(gitmodules, links)
    Dir.mktmpdir do |root|
      git!(root, "init", "-q", "-b", "main", ".")
      git!(root, "config", "user.email", "t@example.com")
      git!(root, "config", "user.name", "Fixture")
      File.write(File.join(root, ".gitmodules"), gitmodules)
      git!(root, "add", ".gitmodules")
      links.each { |path, sha| git!(root, "update-index", "--add", "--cacheinfo", "160000,#{sha},#{path}") }
      git!(root, "-c", "commit.gpgsign=false", "commit", "-qm", "fixture")
      yield root
    end
  end

  describe ".parse_gitmodules" do
    it "reads path+url per submodule and lower-cases keys" do
      text = <<~INI
        [submodule "firmware/extern/mruby"]
        \tpath = firmware/extern/mruby
        \tURL = https://github.com/mruby/mruby
        \tbranch = stable
      INI
      expect(described_class.parse_gitmodules(text)).to eq(
        [ { name: "firmware/extern/mruby", path: "firmware/extern/mruby",
            url: "https://github.com/mruby/mruby", branch: "stable" } ]
      )
    end

    it "returns a header-only entry too — headers are the `--assert` denominator" do
      # A malformed entry must still be COUNTED, otherwise a submodule silently
      # vanishing from the SBOM would also vanish from the drift gate.
      entries = described_class.parse_gitmodules("[submodule \"broken\"]\n[submodule \"ok\"]\n\tpath = p\n\turl = u\n")
      expect(entries.map { |e| e[:name] }).to eq(%w[broken ok])
      expect(entries.first).to eq({ name: "broken" })
    end

    it "ignores comments and stray text outside a section" do
      expect(described_class.parse_gitmodules("# comment\nkey = value\n")).to be_empty
    end
  end

  describe ".normalize_vcs_url" do
    it "collapses the scp form and the https form to ONE identity" do
      expect(described_class.normalize_vcs_url("git@github.com:ARM-software/CMSIS-DSP.git"))
        .to eq("https://github.com/ARM-software/CMSIS-DSP")
      expect(described_class.normalize_vcs_url("https://github.com/ARM-software/CMSIS-DSP.git"))
        .to eq(described_class.normalize_vcs_url("git@github.com:ARM-software/CMSIS-DSP"))
    end

    it "rewrites ssh:// and git:// (dropping any user) and strips a trailing slash" do
      expect(described_class.normalize_vcs_url("ssh://git@gitlab.com/grp/sub/repo.git"))
        .to eq("https://gitlab.com/grp/sub/repo")
      expect(described_class.normalize_vcs_url("git://example.org/repo/")).to eq("https://example.org/repo")
    end

    it "leaves a relative/local url literal — no invented host" do
      # git resolves `../x` against the superproject remote; we do NOT, so the
      # honest output is the literal path, never a guessed https url.
      expect(described_class.normalize_vcs_url("../upstream.git")).to eq("../upstream.git")
      expect(described_class.normalize_vcs_url("/srv/mirrors/repo.git")).to eq("/srv/mirrors/repo.git")
    end
  end

  describe ".github_slug" do
    it "matches only a github.com repo ROOT" do
      expect(described_class.github_slug("https://github.com/leap71/LEAP71_ShapeKernel"))
        .to eq(%w[leap71 LEAP71_ShapeKernel])
      expect(described_class.github_slug("https://github.com/owner/repo/tree/main")).to be_nil
      expect(described_class.github_slug("https://gitlab.com/owner/repo")).to be_nil
    end
  end

  describe ".purl" do
    it "lower-cases namespace+name for pkg:github while the component keeps upstream casing" do
      # purl-spec mandates the lowercase; the asymmetry with `component.name`
      # is correct — identity vs display.
      url = "https://github.com/leap71/LEAP71_ShapeKernel"
      expect(described_class.purl(url, sha_a)).to eq("pkg:github/leap71/leap71_shapekernel@#{sha_a}")
      expect(described_class.component(url:, sha: sha_a)["name"]).to eq("LEAP71_ShapeKernel")
    end

    it "falls back to pkg:generic with a vcs_url for a non-github host" do
      expect(described_class.purl("https://gitlab.com/grp/repo", sha_b))
        .to eq("pkg:generic/repo?vcs_url=git%2Bhttps://gitlab.com/grp/repo%40#{sha_b}")
    end

    it "encodes only `+` and `@` in vcs_url (the purl-spec test-suite form)" do
      purl = described_class.purl("https://git.example.org/a/b", sha_a)
      expect(purl).to include("git%2Bhttps://git.example.org/a/b%40")
      expect(purl).not_to include("%3A", "%2F")
    end
  end

  describe ".parse_status" do
    it "reads the pin for every status flag, including `-` (NOT checked out)" do
      out = <<~OUT
        -#{sha_a} firmware/extern/mruby
         #{sha_b} firmware/extern/CMSIS_6 (v6.3.0)
        +#{sha_a} tools/cad/extern/LEAP71_ShapeKernel (ShapeKernel-v2.1.0-5-g166a459)
        U#{sha_b} vendor/conflicted
      OUT
      expect(described_class.parse_status(out)).to eq(
        "firmware/extern/mruby" => sha_a, "firmware/extern/CMSIS_6" => sha_b,
        "tools/cad/extern/LEAP71_ShapeKernel" => sha_a, "vendor/conflicted" => sha_b
      )
    end

    it "ignores noise lines" do
      expect(described_class.parse_status("fatal: not a git repository\n")).to be_empty
    end
  end

  describe ".component" do
    it "carries group only for github, and pins version = the full 40-char SHA" do
      gh = described_class.component(url: "git@github.com:mruby/mruby.git", sha: sha_a)
      expect(gh).to include("type" => "library", "group" => "mruby", "name" => "mruby",
                            "version" => sha_a)
      expect(gh["bom-ref"]).to eq(gh["purl"])
      expect(gh["externalReferences"]).to eq([ { "type" => "vcs", "url" => "https://github.com/mruby/mruby" } ])
      expect(described_class.component(url: "https://gitlab.com/grp/repo", sha: sha_a)).not_to have_key("group")
    end
  end

  describe ".audit — the real repo (regression guard)" do
    subject(:result) { described_class.audit }

    it "resolves every .gitmodules entry to a component" do
      expect(result[:problems]).to be_empty
      expect(result[:components].size).to eq(result[:entries].size)
    end

    it "emits a CycloneDX 1.6 fragment describing this repo at HEAD" do
      bom = result[:bom]
      expect(bom).to include("bomFormat" => "CycloneDX", "specVersion" => "1.6", "version" => 1)
      expect(bom["metadata"]["component"]).to include("type" => "application", "name" => "silken_net")
      expect(bom).not_to have_key("serialNumber") # fragment — the aggregator mints one
    end

    it "pins every component to a 40-char SHA with a unique bom-ref" do
      refs = result[:components].map { |c| c["bom-ref"] }
      expect(refs.uniq.size).to eq(refs.size)
      expect(result[:components].map { |c| c["version"] }).to all(match(/\A[0-9a-f]{40}\z/))
    end
  end

  describe ".audit — fixture repo (no working tree at all)" do
    it "reads the pin from the index for an uninitialised submodule" do
      ini = "[submodule \"a\"]\n\tpath = vendor/a\n\turl = https://github.com/o/a\n"
      with_fixture_repo(ini, "vendor/a" => sha_a) do |root|
        r = described_class.audit(root:)
        expect(r[:problems]).to be_empty
        expect(r[:components].map { |c| c["purl"] }).to eq([ "pkg:github/o/a@#{sha_a}" ])
      end
    end

    it "flags a duplicate bom-ref — a repeated ref makes the BOM schema-invalid" do
      # Also proves the normalisation: the scp and https spellings of ONE repo
      # collapse to the same identity, which is how the collision surfaces.
      ini = "[submodule \"a\"]\n\tpath = vendor/a\n\turl = git@gitlab.com:grp/a.git\n" \
            "[submodule \"b\"]\n\tpath = vendor/b\n\turl = https://gitlab.com/grp/a\n"
      with_fixture_repo(ini, "vendor/a" => sha_a, "vendor/b" => sha_a) do |root|
        r = described_class.audit(root:)
        expect(r[:components].map { |c| c["purl"] }.uniq.size).to eq(1)
        expect(r[:problems]).to include(a_string_matching(/duplicate bom-ref/))
      end
    end

    it "flags a .gitmodules entry with no gitlink anywhere (the --assert mismatch)" do
      ini = "[submodule \"a\"]\n\tpath = vendor/a\n\turl = https://github.com/o/a\n" \
            "[submodule \"ghost\"]\n\tpath = vendor/ghost\n\turl = https://github.com/o/ghost\n"
      with_fixture_repo(ini, "vendor/a" => sha_a) do |root|
        r = described_class.audit(root:)
        expect(r[:components].size).to eq(1)
        expect(r[:entries].size).to eq(2)
        expect(r[:problems]).to include(a_string_matching(/`ghost`.*no pinned SHA/))
      end
    end

    it "flags an incomplete entry (header present, url missing)" do
      ini = "[submodule \"a\"]\n\tpath = vendor/a\n\turl = https://github.com/o/a\n" \
            "[submodule \"halfling\"]\n\tpath = vendor/halfling\n"
      with_fixture_repo(ini, "vendor/a" => sha_a, "vendor/halfling" => sha_b) do |root|
        r = described_class.audit(root:)
        expect(r[:problems]).to include(a_string_matching(/`halfling`.*incomplete \.gitmodules entry/))
      end
    end
  end

  describe ".timestamp" do
    it "honours SOURCE_DATE_EPOCH so a committed fragment does not churn" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SOURCE_DATE_EPOCH").and_return("1700000000")
      expect(described_class.timestamp).to eq("2023-11-14T22:13:20Z")
    end
  end
end
