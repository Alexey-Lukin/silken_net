# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../scripts/spdx_headers"

# [UNI.3] Unit coverage for the SPDX header rollout engine. Pure functions plus one
# real-git integration pass (no Rails/DB), in the same fixture-driven style as the other
# standalone script guards.
#
# The negative cases carry more weight than the positives here. This engine writes into
# ~1457 tracked files in one campaign, and its two failure modes are both SILENT: a
# header landing in the wrong place (which lints red, or worse, lands inside a block
# comment and simply does not exist), and a scope rule quietly admitting a tree that
# must never be touched (a submodule, an encrypted blob, a generated file).
#
# The single most load-bearing expectation in this file is `#insertion_index` putting the
# tag BEFORE a Ruby magic comment. The written plan prescribed the opposite; measurement
# showed the magic comment survives either way, but a comment placed directly after it
# trips RuboCop's Layout/EmptyLineAfterMagicComment — which would have turned ~999 files
# red in one commit. That expectation is the regression guard for exactly that mistake.
RSpec.describe SpdxHeaders do
  let(:agpl) { described_class::AGPL }

  # ---------------------------------------------------------------- scope: licence_for

  describe ".licence_for" do
    it "assigns AGPL across every ratified code tree" do
      {
        "app/models/tree.rb" => agpl,
        "app/javascript/controllers/theme_controller.js" => agpl,
        "lib/tasks/docs.rake" => agpl,
        "spec/models/tree_spec.rb" => agpl,
        "scripts/docs_check.rb" => agpl,
        "db/seeds.rb" => agpl,
        "config/routes.rb" => agpl,
        "config/database.yml" => agpl,
        "firmware/common/silken_crc.h" => agpl,
        "firmware/soldier/main.c" => agpl,
        "firmware/bio_contracts/bio_contract.rb" => agpl,
        "tools/ml/src/silken_ml/dsp/contract.py" => agpl,
        "tools/cad/src/SilkenCad/TiCoin.cs" => agpl,
        "terraform/main.tf" => agpl,
        "subgraph/src/mapping.ts" => agpl,
        "deploy/grafana/import.rb" => agpl,
        "bin/bootstrap_github.sh" => agpl
      }.each { |path, want| expect(described_class.licence_for(path)).to eq(want), "#{path} should be #{want}" }
    end

    it "keeps contracts/ on the ratified MIT exception (DOC-T.47)" do
      expect(described_class.licence_for("contracts/SilkenCarbonCoin.sol")).to eq(described_class::MIT)
      expect(described_class.licence_for("contracts/test/Deploy.t.sol")).to eq(described_class::MIT)
    end

    # Each of these is a distinct way the sweep could damage something.
    it "refuses every out-of-scope path" do
      [
        "firmware/extern/mruby/src/vm.c",            # git submodule — another repo's code
        "tools/cad/extern/LEAP71_ShapeKernel/x.cs",  # ditto
        "contracts/node_modules/oz/ERC20.sol",       # gitignored npm install
        "contracts/out/SCC.json",                    # forge build output
        "docs/07_03_Academic_Integration_and_IP.md", # CC-BY-SA, no per-file tag
        "config/credentials.yml.enc",                # encrypted blob
        "config/credentials/production.key",         # key material
        "db/structure.sql",                          # pg_dump regenerates it
        "config/locales/en.yml",                     # i18n-tasks re-renders byte-for-byte
        "config/locales/codex/uk.yml",               # ditto, at any depth
        "app/views/layouts/application.html.erb",    # emits into rendered output
        "spec/components/previews/x/all.html.erb",   # ditto
        "public/404.html",
        "vendor/javascript/x.js",
        ".github/workflows/ci.yml",
        ".claude/skills/backend/SKILL.md",
        ".kamal/hooks/pre-deploy",
        "tools/cad/cem/anchor.json",                 # JSON has no comment syntax
        "bin/rails",                                 # generated binstub, not our work
        "firmware/CMakeLists.txt",                   # build plumbing
        "README.md"
      ].each { |path| expect(described_class.licence_for(path)).to be_nil, "#{path} must stay untouched" }
    end

    it "is an allow-list: an unlisted extension in a listed tree is still out of scope" do
      expect(described_class.licence_for("app/assets/images/logo.svg")).to be_nil
      expect(described_class.licence_for("tools/in_silico/data/geom.xyz")).to be_nil
      expect(described_class.licence_for("firmware/sim/wle5_bench/stm32wle5.ld")).to be_nil
    end

    it "is an allow-list: a listed extension in an unlisted tree is still out of scope" do
      expect(described_class.licence_for("some_new_tree/thing.rb")).to be_nil
    end

    it "denies extern/ at any depth, not only at the tree root" do
      expect(described_class.licence_for("tools/cad/extern/deep/nested/File.cs")).to be_nil
      expect(described_class.licence_for("firmware/extern/CMSIS_6/Core/Include/core_cm4.h")).to be_nil
    end
  end

  # ------------------------------------------------------------- comment prefix per lang

  describe ".comment_prefix" do
    it "maps the hash-comment languages" do
      %w[a.rb a.rake a.py a.sh a.tf a.yml a.yaml].each do |name|
        expect(described_class.comment_prefix(name, "x")).to eq("#"), "#{name} should use #"
      end
    end

    it "maps the slash-comment languages" do
      %w[a.c a.h a.cs a.ts a.js a.sol].each do |name|
        expect(described_class.comment_prefix(name, "x")).to eq("//"), "#{name} should use //"
      end
    end

    # lib/daemons/coap_listener is the only such file today, and the plan names it.
    it "accepts an extensionless file when a shebang names a #-comment interpreter" do
      expect(described_class.comment_prefix("lib/daemons/coap_listener", "#!/usr/bin/env ruby\n")).to eq("#")
      expect(described_class.comment_prefix("x/thing", "#!/bin/bash\n")).to eq("#")
      expect(described_class.comment_prefix("x/thing", "#!/usr/bin/python3\n")).to eq("#")
    end

    it "refuses an extensionless file without a recognised shebang" do
      expect(described_class.comment_prefix("x/thing", "some data\n")).to be_nil
      expect(described_class.comment_prefix("x/thing", "#!/usr/bin/env node\n")).to be_nil
      expect(described_class.comment_prefix("x/thing", nil)).to be_nil
    end
  end

  # ------------------------------------------------------------------- insertion point

  describe ".insertion_index" do
    # 🔴 THE REGRESSION GUARD. See the file header: after the magic comment is a RuboCop
    # offence (Layout/EmptyLineAfterMagicComment) on ~999 files; before it is clean and
    # the magic comment still applies (measured on Ruby 4.0.5 with a negative control).
    # Asserted on the RESULTING line order, not on the index: the index alone cannot
    # express "ends up above the magic comment", because inserting AT the magic comment's
    # current position is exactly what pushes it down. The property under test is the
    # shape of the file after the write, so that is what the test looks at.
    def order_after_insert(path, lines)
      out = lines.dup
      out.insert(described_class.insertion_index(path, lines), "# SPDX-License-Identifier: X\n")
      [ out.index { |l| l.include?("SPDX") }, out.index { |l| l.include?("frozen_string_literal") }, out ]
    end

    it "puts the tag BEFORE a Ruby magic comment, never after it" do
      spdx, magic, out = order_after_insert("app/models/foo.rb",
                                            [ "# frozen_string_literal: true\n", "\n", "class Foo\n", "end\n" ])

      expect(spdx).to be < magic
      expect(out.first).to include("SPDX")
    end

    it "puts the tag after a shebang but still before the magic comment" do
      spdx, magic, out = order_after_insert("scripts/x.rb",
                                            [ "#!/usr/bin/env ruby\n", "# frozen_string_literal: true\n", "\n", "puts 1\n" ])

      expect(out.first).to start_with("#!")   # a shebang must stay on line 1 or the file stops being executable
      expect(spdx).to eq(1)
      expect(spdx).to be < magic
    end

    it "uses line 1 when the file opens straight into code or a plain comment" do
      expect(described_class.insertion_index("app/x.rb", [ "class Foo\n" ])).to eq(0)
      expect(described_class.insertion_index("app/x.rb", [ "# a plain banner\n" ])).to eq(0)
    end

    it "keeps a Python shebang first and tolerates a module docstring below" do
      lines = [ "#!/usr/bin/env python\n", "\"\"\"Doc.\"\"\"\n" ]
      expect(described_class.insertion_index("tools/ml/x.py", lines)).to eq(1)
      expect(described_class.insertion_index("tools/ml/x.py", [ "\"\"\"Doc.\"\"\"\n" ])).to eq(0)
    end

    it "keeps a shell shebang first" do
      expect(described_class.insertion_index("firmware/scripts/x.sh", [ "#!/usr/bin/env bash\n", "set -e\n" ])).to eq(1)
    end

    # A CubeMX regen rewrites everything outside the USER CODE markers. A tag placed above
    # the marker is silently dropped on the next regen; inside it survives.
    it "places the tag INSIDE the CubeMX USER CODE Header block" do
      lines = [ "/* USER CODE BEGIN Header */\n", "/**\n", "  * @file : main.c\n", "  */\n",
               "/* USER CODE END Header */\n", "#include \"main.h\"\n" ]
      idx = described_class.insertion_index("firmware/soldier/main.c", lines)

      expect(idx).to eq(1)
      expect(lines[idx - 1]).to include("USER CODE BEGIN Header")
      # and strictly above the END marker, or a regen eats it
      expect(idx).to be < lines.index { |l| l.include?("USER CODE END Header") }
    end

    it "uses line 1 for a plain C file, above its banner block comment" do
      expect(described_class.insertion_index("firmware/common/silken_crc.h", [ "/*\n", " * banner\n", " */\n" ])).to eq(0)
    end

    it "keeps a YAML document-start or directive first" do
      expect(described_class.insertion_index("config/database.yml", [ "---\n", "en:\n" ])).to eq(1)
      expect(described_class.insertion_index("config/x.yml", [ "%YAML 1.2\n", "---\n" ])).to eq(1)
      expect(described_class.insertion_index("config/x.yml", [ "default: &default\n" ])).to eq(0)
    end
  end

  # ------------------------------------------------------------------- tag detection

  describe ".existing_tag" do
    it "reads the identifier back out of a tagged file" do
      expect(described_class.existing_tag([ "# SPDX-License-Identifier: AGPL-3.0-or-later\n" ])).to eq(agpl)
      expect(described_class.existing_tag([ "// SPDX-License-Identifier: MIT\n", "pragma solidity;\n" ])).to eq("MIT")
    end

    it "finds a tag nested in a CubeMX header block" do
      lines = [ "/* USER CODE BEGIN Header */\n", "// SPDX-License-Identifier: AGPL-3.0-or-later\n", "/**\n" ]
      expect(described_class.existing_tag(lines)).to eq(agpl)
    end

    it "returns nil for an untagged file" do
      expect(described_class.existing_tag([ "# frozen_string_literal: true\n", "class Foo\n" ])).to be_nil
    end

    # The window is bounded on purpose: an unbounded scan would false-skip any file that
    # merely discusses the identifier. Proving the bound is what keeps that honest.
    it "does not look past its scan window" do
      lines = Array.new(described_class::SCAN_LINES, "# filler\n") + [ "# SPDX-License-Identifier: MIT\n" ]
      expect(described_class.existing_tag(lines)).to be_nil
    end
  end

  # ---------------------------------------------------------- integration over real git

  describe ".plan and .apply! over a real git tree" do
    # `plan` enumerates through `git ls-files`, so the fixture has to be a real index.
    def with_repo(files)
      Dir.mktmpdir do |root|
        files.each do |rel, body|
          path = File.join(root, rel)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, body)
        end
        system("git", "-C", root, "init", "-q", exception: true)
        system("git", "-C", root, "add", "-A", exception: true)
        yield root
      end
    end

    let(:tree) do
      {
        "app/models/tree.rb" => "# frozen_string_literal: true\n\nclass Tree; end\n",
        "scripts/run.rb" => "#!/usr/bin/env ruby\n# frozen_string_literal: true\n\nputs 1\n",
        "config/database.yml" => "---\nen:\n  hello: Hi\n",
        "firmware/common/crc.h" => "/*\n * banner\n */\n#define X 1\n",
        "tools/ml/dsp.py" => "#!/usr/bin/env python\n\"\"\"Doc.\"\"\"\n",
        "contracts/SCC.sol" => "// SPDX-License-Identifier: MIT\npragma solidity;\n",
        "docs/00_01.md" => "# doc\n",
        "db/structure.sql" => "SET x = 0;\n",
        "app/views/layouts/app.html.erb" => "<!DOCTYPE html>\n"
      }
    end

    it "plans exactly the in-scope files and leaves the rest alone" do
      with_repo(tree) do |root|
        actions = described_class.plan(root:, paths: [])
        by_path = actions.to_h { |a| [ a[:path], a ] }

        expect(by_path.keys).to match_array(%w[
          app/models/tree.rb scripts/run.rb config/database.yml
          firmware/common/crc.h tools/ml/dsp.py contracts/SCC.sol
        ])
        expect(by_path["contracts/SCC.sol"][:status]).to eq(:ok)
        expect(by_path.except("contracts/SCC.sol").values.map { |a| a[:status] }).to all(eq(:insert))
      end
    end

    it "writes each header at the language-correct position" do
      with_repo(tree) do |root|
        described_class.plan(root:, paths: []).select { |a| a[:status] == :insert }
                       .each { |a| described_class.apply!(root, a) }

        expect(File.read(File.join(root, "app/models/tree.rb")).lines.first(2))
          .to eq([ "# SPDX-License-Identifier: #{agpl}\n", "# frozen_string_literal: true\n" ])
        expect(File.read(File.join(root, "scripts/run.rb")).lines.first(3))
          .to eq([ "#!/usr/bin/env ruby\n", "# SPDX-License-Identifier: #{agpl}\n", "# frozen_string_literal: true\n" ])
        expect(File.read(File.join(root, "config/database.yml")).lines.first(2))
          .to eq([ "---\n", "# SPDX-License-Identifier: #{agpl}\n" ])
        expect(File.read(File.join(root, "firmware/common/crc.h")).lines.first)
          .to eq("// SPDX-License-Identifier: #{agpl}\n")
        expect(File.read(File.join(root, "tools/ml/dsp.py")).lines.first(2))
          .to eq([ "#!/usr/bin/env python\n", "# SPDX-License-Identifier: #{agpl}\n" ])
      end
    end

    it "is idempotent — a second pass plans nothing and changes no byte" do
      with_repo(tree) do |root|
        described_class.plan(root:, paths: []).select { |a| a[:status] == :insert }
                       .each { |a| described_class.apply!(root, a) }
        after_first = tree.keys.to_h { |rel| [ rel, File.read(File.join(root, rel)) ] }

        second = described_class.plan(root:, paths: [])
        expect(second.select { |a| a[:status] == :insert }).to be_empty
        expect(second.map { |a| a[:status] }).to all(eq(:ok))

        second.each { |a| described_class.apply!(root, a) if a[:status] == :insert }
        expect(tree.keys.to_h { |rel| [ rel, File.read(File.join(root, rel)) ] }).to eq(after_first)
      end
    end

    it "reports a foreign identifier as a mismatch and never rewrites it" do
      with_repo("app/models/tree.rb" => "# SPDX-License-Identifier: Apache-2.0\nclass Tree; end\n") do |root|
        action = described_class.plan(root:, paths: []).first
        before = File.read(File.join(root, "app/models/tree.rb"))

        expect(action[:status]).to eq(:mismatch)
        expect(action[:found]).to eq("Apache-2.0")
        expect(File.read(File.join(root, "app/models/tree.rb"))).to eq(before)
      end
    end

    it "narrows to the requested trees so a rollout can go one tree at a time" do
      with_repo(tree) do |root|
        expect(described_class.plan(root:, paths: [ "app" ]).map { |a| a[:path] }).to eq([ "app/models/tree.rb" ])
      end
    end

    it "skips an empty file rather than creating a header-only file" do
      with_repo("tools/in_silico/lib/__init__.py" => "") do |root|
        expect(described_class.plan(root:, paths: [])).to be_empty
      end
    end

    it "skips a binary that slipped past the extension allow-list" do
      with_repo("app/models/blob.rb" => "\x00\x01\x02binary") do |root|
        expect(described_class.plan(root:, paths: [])).to be_empty
      end
    end

    it "preserves CRLF line endings when a file uses them" do
      with_repo("app/models/tree.rb" => "# frozen_string_literal: true\r\nclass Tree; end\r\n") do |root|
        action = described_class.plan(root:, paths: []).first
        described_class.apply!(root, action)

        expect(File.binread(File.join(root, "app/models/tree.rb")).lines.first)
          .to eq("# SPDX-License-Identifier: #{agpl}\r\n")
      end
    end
  end
end
