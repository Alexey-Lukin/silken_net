# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Lints Phlex views for raw Tailwind colour utilities that should be design
# tokens (docs/04_04 § 3.1) — and its DEFAULT PERIMETER is the surface where
# that rule is actually binding.
#
# 🔴 [UI.1] The default used to be `app/views/components/`, which inverted the
# gate: `04_04 § 3.5` EXPLICITLY ALLOWS raw Tailwind in domain page-components
# ("вони не переповикористовуються у різних контекстах") and FORBIDS it in
# `app/views/shared/**`. So the linter scanned the permissive surface — where a
# hit is not a violation — and was blind to the strict one, which it never
# looked at at all. Measured at the flip: shared/ = 0 hits over every file,
# components/ = several hundred legal ones.
#
#   bin/rails gaia:lint_tokens                          # shared/ — the HARD rule
#   COMPONENTS=app/views/components/wallets/ \
#     bin/rails gaia:lint_tokens                        # any subtree, on demand
#
# ⚠️ `app/views/layouts/` is deliberately OUT of the default: measured, its one
# hit is `backdrop:bg-black/60` — the scrim behind the mobile drawer, which must
# stay black in BOTH themes (a surface token there would make the light-theme
# scrim pale). Adding layouts means adding that allowlist entry first.
#
# ⚠️ COMPONENTS= takes ONE path. The `.then` below branches on `directory?`, so a
# space-separated pair yields a non-directory Pathname and silently lints one
# nonexistent file — green with zero files scanned, the decorative-gate shape.
#
# Allowlist: see `allowlist` below — brand / decorative colours that are raw on
# purpose (e.g. `bg-emerald-500/10` for the login button's brand-glow).
namespace :gaia do
  desc "Find raw Tailwind colour utilities in shared Phlex primitives (compliance check)"
  task lint_tokens: :environment do
    paths = (ENV["COMPONENTS"] || "app/views/shared/").then do |p|
      Pathname.new(p).directory? ? Pathname.glob("#{p}/**/*.rb") : [ Pathname.new(p) ]
    end

    # Patterns that indicate a class slipped past gaia-token migration.
    raw_patterns = [
      /\b(bg-(?:white|black|gray-\d+))\b/,
      /\b(text-(?:white|gray-\d+|emerald-(?:400|500|600|700|800|900)))\b/,
      /\b(border-(?:gray-\d+|emerald-(?:700|800|900)))\b/
    ]

    # Decorative / brand allowlist — these are intentional and not migrated.
    allowlist = [
      "bg-emerald-500/10",  # login submit brand glow
      "bg-emerald-500/20",  # impedance bar fill
      "bg-emerald-500",     # brand pulse / animate-ping accents
      "border-emerald-500/20" # spinner ring
    ]

    violations = []
    paths.each do |path|
      next unless path.extname == ".rb"

      path.each_line.with_index(1) do |line, lineno|
        # Strip allowlisted brand tokens before scanning.
        scrubbed = line.dup
        allowlist.each { |a| scrubbed.gsub!(a, "") }

        raw_patterns.each do |re|
          scrubbed.scan(re).each do |hit|
            klass = hit.is_a?(Array) ? hit.compact.first : hit
            violations << { file: path.to_s, line: lineno, klass: klass }
          end
        end
      end
    end

    if violations.empty?
      puts "✓ gaia:lint_tokens — no raw Tailwind colour utilities detected"
      next
    end

    puts "✗ gaia:lint_tokens — #{violations.size} raw Tailwind class(es) detected:"
    violations.group_by { |v| v[:file] }.each do |file, items|
      puts "  #{file}"
      items.each { |i| puts "    L#{i[:line]}: #{i[:klass]}" }
    end
    puts ""
    puts "Migrate via: bin/migrate-tailwind-tokens #{violations.first[:file]}"
    puts "Mapping reference: docs/04_04_Phlex_UI_and_Tailwind.md § 3.1"
    abort
  end
end
