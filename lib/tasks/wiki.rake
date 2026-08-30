# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [OPS] `rake wiki:sync` — publish the canonical SSOT docs (docs/NN_NN_*.md) to
# the GitHub wiki (a separate git repo whose pages are named after the docs;
# 00_00 → the `Home` landing page). Auto-runs on docs-change pushes to main via
# `.github/workflows/wiki.yml` (gated by repo var DISABLE_WIKI_AUTOSYNC); also by hand:
#
#   bin/rails wiki:sync          # DRY-RUN: clone wiki, transform, show diff, do NOT push
#   bin/rails wiki:sync PUSH=1   # commit + push the changes to the wiki
#
# Only NN_NN_*.md canonical docs are synced (manifest.md and everything else is
# left out). Links are normalised for the wiki (see lib/wiki_link_normalizer.rb):
# canonical cross-refs → bare wiki links, other repo files → absolute github.com
# blob URLs, embedded images carried into the wiki under images/. Local runs use
# SSH; CI (wiki.yml) passes an HTTPS x-access-token remote via WIKI_REMOTE.
#
# Pure file/git I/O (no Rails boot needed). Engine: lib/wiki_link_normalizer.rb.
require_relative "../wiki_link_normalizer"
require "tmpdir"
require "fileutils"

namespace :wiki do
  # Constants kept as task-locals to avoid clobbering other rake files' globals
  # (rake `namespace` blocks define constants at top level, not in a module).
  desc "Publish canonical docs/NN_NN_*.md to the GitHub wiki (dry-run unless PUSH=1)"
  task :sync do
    repo_slug   = "Alexey-Lukin/silken_net"
    # SSH by default (local dev); CI passes an HTTPS x-access-token remote via WIKI_REMOTE.
    wiki_remote = ENV.fetch("WIKI_REMOTE") { "git@github.com:#{repo_slug}.wiki.git" }
    # The 00_00 SSOT index is published as the wiki landing page `Home`, not a `00_00…` page.
    home_doc    = "00_00_SSOT_Index.md"
    repo_root   = File.expand_path("../../", __dir__)
    docs_dir    = File.join(repo_root, "docs")
    canon_glob  = "[0-9][0-9]_[0-9][0-9]_*.md"

    push  = ENV["PUSH"] == "1"
    canon = Dir.children(docs_dir).select { |f| File.fnmatch(canon_glob, f) }.sort
    abort "wiki:sync — no canonical docs found in #{docs_dir}" if canon.empty?
    slugs = canon.map { |f| File.basename(f, ".md") }

    head = `git -C #{repo_root} rev-parse --short HEAD`.strip
    exists = ->(rel) { File.exist?(File.join(repo_root, rel)) }
    normalizer = WikiLinkNormalizer.new(canon_slugs: slugs, repo: repo_slug, exists: exists,
                                        home_slug: File.basename(home_doc, ".md"))

    Dir.mktmpdir("silken-wiki-") do |tmp|
      wiki = File.join(tmp, "wiki")
      unless system("git", "clone", "--quiet", "--depth", "1", wiki_remote, wiki)
        abort "wiki:sync — could not clone #{wiki_remote}. Check SSH access to the wiki repo."
      end
      FileUtils.mkdir_p(File.join(wiki, "images"))

      # 1. Mirror: drop wiki NN_NN_*.md pages that no longer have a source doc.
      #    Curated pages (Home, _Sidebar, _Footer, …) and images/ are preserved.
      Dir.children(wiki).select { |f| File.fnmatch(canon_glob, f) && !canon.include?(f) }.each do |orphan|
        File.delete(File.join(wiki, orphan))
        puts "  − removed orphaned wiki page: #{orphan}"
      end
      # 00_00 is now published as `Home`; drop any stale 00_00_SSOT_Index page.
      if File.exist?(File.join(wiki, home_doc))
        File.delete(File.join(wiki, home_doc))
        puts "  − removed #{home_doc} (now published as Home)"
      end

      # 2. Transform + write each canonical doc; carry referenced images over.
      unresolved = {}
      canon.each do |fname|
        res = normalizer.call(File.read(File.join(docs_dir, fname)))
        page = fname == home_doc ? "Home.md" : fname
        File.write(File.join(wiki, page), res.body)
        res.images.each do |img|
          FileUtils.cp(File.join(repo_root, img), File.join(wiki, "images", File.basename(img)))
        end
        unresolved[fname] = res.unresolved unless res.unresolved.empty?
      end

      # 3. Diff + (optionally) push.
      Dir.chdir(wiki) do
        system("git", "add", "-A")
        if system("git", "diff", "--cached", "--quiet")
          puts "wiki:sync — wiki already up to date (no changes)."
        else
          puts "── staged changes ──"
          system("git", "--no-pager", "diff", "--cached", "--stat")
          if push
            system("git", "-c", "user.name=SilkenNet Docs Bot", "-c", "user.email=docs@silkennet.com",
                   "commit", "--quiet", "-m", "docs: sync SSOT canon from repo @ #{head}")
            abort "wiki:sync — git push failed." unless system("git", "push", "--quiet", "origin", "HEAD")
            puts "✅ wiki:sync — published #{canon.size} pages."
          else
            puts "\n── DRY-RUN — nothing pushed. Review above, then: bin/rails wiki:sync PUSH=1 ──"
          end
        end
      end

      unless unresolved.empty?
        puts "\n⚠️  links left untouched (target not found in repo — likely stale in source):"
        unresolved.each { |doc, links| links.each { |l| puts "   #{doc}: #{l}" } }
      end
    end
  end
end
