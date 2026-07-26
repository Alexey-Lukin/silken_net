#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# scripts/wiki_sync.rb — run `wiki:sync` WITHOUT booting Rails (CI / pre-commit).
#
# Loads the rake task directly (it requires only stdlib + lib/wiki_link_normalizer),
# so CI needs just Ruby + git — no bundle, no DB, no Rails boot, no master-key
# initializer. Reuses the exact rake body → cannot drift from `bin/rails wiki:sync`.
#
# Honours the same env as the rake task:
#   PUSH=1        — publish (default: dry-run, nothing pushed)
#   WIKI_REMOTE=… — override the wiki git remote (CI passes an HTTPS x-access-token URL;
#                   local default is SSH `git@github.com:…wiki.git`)
require "rake"
load File.expand_path("../lib/tasks/wiki.rake", __dir__)
Rake::Task["wiki:sync"].invoke
