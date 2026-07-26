# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# = =====================================================================
# 📓 LOOKBOOK YARD TAG REGISTRATION
# = =====================================================================
# Lookbook component previews use YARD-style annotations (e.g. `@label`,
# `@display`, `@notes`) to drive the preview browser UI. The `@notes`
# scenario tag is documented by Lookbook (`Lookbook::Preview` scenario
# notes), but YARD itself only ships the singular `@note` tag, so when
# Lookbook eagerly parses the previews on boot every `@notes` line emits
# a noisy warning:
#
#   [warn]: Unknown tag @notes in file `.../*_preview.rb` near line N
#
# Multiplied by ~50 previews × several scenarios each this floods the
# console during `rails`, `rails db:migrate`, `rspec`, etc., drowning real
# diagnostics. We register `@notes` as a free-form text tag so YARD parses
# it as documentation metadata instead of warning. Loaded only when YARD
# is actually present (development / test via Lookbook); production stays
# untouched (Lookbook is mounted only in development per config/routes.rb).
if defined?(YARD)
  YARD::Tags::Library.define_tag("Notes", :notes)
end
