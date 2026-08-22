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
        "app/javascript/controllers/map_controller.js" => agpl,
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
        # 🔴 Extensionless and named-by-basename files. The first of these is the one that
        # matters: it was written as `%w[.rb .rake ""]`, where `""` is a two-character
        # string and not the empty one, so the extensionless rule matched NOTHING and the
        # single file the plan names by hand was silently skipped. One composed assertion
        # here — licence_for, not just comment_prefix — kills that class at birth.
        "lib/daemons/coap_listener" => agpl,
        "bin/coap_load" => agpl,
        "bin/forest_simulator" => agpl,
        "firmware/test/Makefile" => agpl,
        "firmware/CMakeLists.txt" => agpl,
        "firmware/cmake/arm-none-eabi.cmake" => agpl,
        "firmware/sim/wle5_bench/stm32wle5.ld" => agpl,
        "app/assets/tailwind/application.css" => agpl,
        "lib/canonical_block_pins.yml" => agpl,
        "subgraph/schema.graphql" => agpl,
        "subgraph/subgraph.yaml" => agpl
      }.each { |path, want| expect(described_class.licence_for(path)).to eq(want), "#{path} should be #{want}" }
    end

    it "leaves the generated bin/ binstubs alone — bin membership is enumerated, not patterned" do
      %w[bin/rails bin/rake bin/rspec bin/rubocop bin/setup bin/dev bin/docker-entrypoint]
        .each { |path| expect(described_class.licence_for(path)).to be_nil, "#{path} is generated" }
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
        "docs/00_02_Academic_Integration_and_IP.md", # CC-BY-SA, no per-file tag
        "config/credentials.yml.enc",                # encrypted blob
        "config/credentials/production.key",         # key material
        "db/structure.sql",                          # pg_dump regenerates it
        "db/cable_schema.rb",                        # SchemaDumper rewrites it — tag not durable
        "db/cache_schema.rb",                        # ditto
        "config/locales/en.yml",                     # i18n-tasks re-renders byte-for-byte
        "config/locales/navigation/uk.yml",          # ditto, at any depth
        "tools/in_silico/conda-lock.yml",            # third-party lock output
        "firmware/hal_glue/stm32wlxx_hal_conf.h",    # © STMicroelectronics — adjudicated
        "firmware/queen/lorawan_glue/se-identity.h", # Semtech BSD — adjudicated
        "app/views/layouts/application.html.erb",    # emits into rendered output
        "spec/components/previews/x/all.html.erb",   # ditto
        "public/404.html",
        "vendor/javascript/x.js",
        ".github/workflows/ci.yml",
        ".claude/skills/backend/SKILL.md",
        ".kamal/hooks/pre-deploy",
        "tools/cad/cem/anchor.json",                 # JSON has no comment syntax
        "bin/rails",                                 # generated binstub, not our work
        "firmware/.cppcheck/stm32wle5.xml",           # tool platform definition
        "README.md"
      ].each { |path| expect(described_class.licence_for(path)).to be_nil, "#{path} must stay untouched" }
    end

    it "is an allow-list: an unlisted extension in a listed tree is still out of scope" do
      expect(described_class.licence_for("app/assets/images/logo.svg")).to be_nil
      expect(described_class.licence_for("tools/in_silico/data/geom.xyz")).to be_nil
      expect(described_class.licence_for("firmware/notes.md")).to be_nil
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

    it "uses line 1 for every language with no leading-line ceremony" do
      %w[a.sol a.ts a.js a.cs a.tf a.graphql a.css a.ld].each do |name|
        expect(described_class.insertion_index(name, [ "first line\n" ])).to eq(0), "#{name} should insert at 0"
      end
    end

    # The idempotency invariant, stated once instead of implied by two separate examples:
    # a tag placed at or beyond the detection window would be invisible to the next run,
    # which would then insert a second one.
    it "never returns an index at or beyond the tag-detection window" do
      cubemx = Array.new(30) { |i| i == 20 ? "/* USER CODE BEGIN Header */\n" : "x\n" }
      [ [ "firmware/x.c", cubemx ], [ "a.rb", [ "#!/x\n" ] ], [ "a.yml", [ "---\n" ] ] ].each do |path, lines|
        expect(described_class.insertion_index(path, lines)).to be < described_class::SCAN_LINES
      end
    end

    it "sees past a UTF-8 BOM so a shebang keeps line 1" do
      expect(described_class.insertion_index("a.sh", [ "﻿#!/bin/sh\n", "x\n" ])).to eq(1)
      expect(described_class.insertion_index("a.yml", [ "﻿---\n", "x\n" ])).to eq(1)
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

  # ------------------------------------------------------------ third-party notices

  # 🔴 The second load-bearing guard. Stamping our identifier above someone else's
  # copyright is a false licence claim on third-party code — the most expensive error
  # available in a defensive-publication posture, and invisible to `existing_tag`
  # because a prose vendor notice contains no `SPDX-License-Identifier` string.
  describe ".foreign_notice" do
    it "catches the real vendor notices present in this repo" do
      [
        " * Copyright (c) 2020 STMicroelectronics.\n",
        " *              (C)2020 Semtech\n",
        " *          Portions COPYRIGHT 2020 STMicroelectronics\n",
        " * \\copyright Revised BSD License, see section \\ref LICENSE.\n",
        " * All rights reserved.\n"
      ].each { |line| expect(described_class.foreign_notice([ line ])).not_to be_nil, "should flag: #{line.strip}" }
    end

    it "scans past a leading ASCII-art logo" do
      lines = [ "/*!\n" ] + Array.new(12) { " *   ___\n" } + [ " *   (C)2020 Semtech\n" ]
      expect(described_class.foreign_notice(lines)).to include("Semtech")
    end

    # The word alone must not trip it: scripts/dco_check.rb discusses copyright in prose.
    it "does not trip on the word 'copyright' without an attribution" do
      [
        "# copyright-origin certification the AGPL posture leans on (00_01 §8)\n",
        "# Every contributor certifies copyright origin via the DCO.\n",
        "# See the copyright section of NOTICE.\n"
      ].each { |line| expect(described_class.foreign_notice([ line ])).to be_nil, "false positive on: #{line.strip}" }
    end

    it "stops looking after its window" do
      lines = Array.new(described_class::NOTICE_SCAN_LINES, "# filler\n") + [ "# Copyright (c) 2020 Acme\n" ]
      expect(described_class.foreign_notice(lines)).to be_nil
    end

    # Without this, adding our OWN copyright header to a file would drop it out of the
    # rollout and out of the gate in the same motion — the guard turning on its owner.
    it "does not treat OUR copyright as foreign" do
      [
        "# Copyright (c) 2026 Oleksii Lukin / SilkenNet\n",
        "# Copyright 2026 Silken Net. All rights reserved.\n",
        "// © 2026 GaiaNexus\n"
      ].each { |line| expect(described_class.foreign_notice([ line ])).to be_nil, "ours, not foreign: #{line.strip}" }
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

    it "refuses to stamp a file carrying a third-party copyright, leaving it byte-identical" do
      vendor = "/*\n * hal_conf.h — our preamble\n */\n/**\n  * Copyright (c) 2020 STMicroelectronics.\n  */\n"
      with_repo("firmware/hal_glue/vendor.h" => vendor) do |root|
        action = described_class.plan(root:, paths: []).first

        expect(action[:status]).to eq(:foreign_notice)
        expect(action[:notice]).to include("STMicroelectronics")
        expect(File.read(File.join(root, "firmware/hal_glue/vendor.h"))).to eq(vendor)
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

    # apply! carries its own status guard rather than trusting the caller's filter: on an
    # :ok record it would double the tag, on :mismatch / :foreign_notice it would write our
    # licence directly above somebody else's.
    it "is a no-op on any record that is not :insert" do
      tree = {
        "app/models/ok.rb" => "# SPDX-License-Identifier: #{agpl}\nclass A; end\n",
        "app/models/other.rb" => "# SPDX-License-Identifier: Apache-2.0\nclass B; end\n",
        "firmware/v.h" => "/* Copyright (c) 2020 Acme Corp. */\n#define X 1\n"
      }
      with_repo(tree) do |root|
        before = tree.keys.to_h { |rel| [ rel, File.read(File.join(root, rel)) ] }
        actions = described_class.plan(root:, paths: [])

        expect(actions.map { |a| a[:status] }).to match_array(%i[ok mismatch foreign_notice])
        actions.each { |a| expect(described_class.apply!(root, a)).to be_nil }
        expect(tree.keys.to_h { |rel| [ rel, File.read(File.join(root, rel)) ] }).to eq(before)
      end
    end

    it "does not glue the tag onto a final line that has no newline" do
      with_repo("bin/coap_load" => "#!/usr/bin/env ruby") do |root|
        action = described_class.plan(root:, paths: []).first
        described_class.apply!(root, action)

        expect(File.readlines(File.join(root, "bin/coap_load")))
          .to eq([ "#!/usr/bin/env ruby\n", "# SPDX-License-Identifier: #{agpl}\n" ])
      end
    end

    it "survives an invalid UTF-8 byte instead of aborting the whole run" do
      with_repo("app/models/tree.rb" => "# caf\xE9 in a comment\nclass Tree; end\n") do |root|
        expect { described_class.plan(root:, paths: []) }.not_to raise_error
      end
    end

    it "refuses to enumerate outside a git repository rather than reporting an empty tree" do
      Dir.mktmpdir { |root| expect { described_class.plan(root:, paths: []) }.to raise_error(/git ls-files failed/) }
    end

    # The allow-list's blind spot, made loud. Probing the gate (not reading it) showed a
    # source file in a brand-new top-level directory was invisible: not flagged, not
    # counted, not mentioned. `unclassified` turns that silence into a decision request.
    describe ".unclassified" do
      it "reports a source file in a tree no rule covers" do
        with_repo("newmodule/orphan.rb" => "class Orphan; end\n") do |root|
          expect(described_class.plan(root:, paths: [])).to be_empty
          expect(described_class.unclassified(root)).to eq([ "newmodule/orphan.rb" ])
        end
      end

      it "stays quiet for a covered tree, a denied path, and a non-code extension" do
        with_repo(
          "app/models/tree.rb" => "class Tree; end\n",
          "docs/x.md" => "# doc\n",
          "config/locales/en.yml" => "---\nen:\n",
          "newmodule/data.xyz" => "0 0 0\n"
        ) { |root| expect(described_class.unclassified(root)).to be_empty }
      end

      it "is empty for the real repository — every tree is adjudicated" do
        expect(described_class.unclassified(File.expand_path("../..", __dir__))).to be_empty
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
