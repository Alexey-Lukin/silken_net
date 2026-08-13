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
#
# 🔴 NO `:environment` PREREQUISITE, and that is load-bearing rather than tidy.
# The body is pure Ruby (Pathname + ENV), and its docs.yml neighbours —
# `docs:check_refs`, `tracker:check` — declare no `:environment` either, so that
# job has never booted the app and its runner carries no native libvips. With
# the prerequisite in place the step died at `ActiveStorage::Transformers::Vips`
# before the linter ran a single line: green locally, red in CI, for a reason
# that has nothing to do with what the gate checks.
require "pathname"

namespace :gaia do
  desc "Find raw Tailwind colour utilities in shared Phlex primitives (compliance check)"
  task :lint_tokens do
    paths = (ENV["COMPONENTS"] || "app/views/shared/").then do |p|
      Pathname.new(p).directory? ? Pathname.glob("#{p}/**/*.rb") : [ Pathname.new(p) ]
    end

    # 🔴 Tailwind має ПʼЯТЬ нейтральних родин, і доти regex знав рівно одну
    # (`gray`) — тобто `bg-zinc-950` проходив навіть у `shared/`, де сира
    # Tailwind заборонена HARD. Діра не теоретична: саме `bg-zinc-950` під
    # токенізованим текстом робив світлу половину `--gaia-text-subtle`
    # арифметично нездійсненною (`00_07` UI.3). Розширення безпечне для чинного
    # периметра — виміряно перед внесенням: у `app/views/shared/**` нуль хітів
    # чотирьох дописаних родин, тож ratchet «migrate-to-green ПЕРЕД гейтом»
    # виконано без міграції.
    neutrals = "gray|zinc|neutral|slate|stone"

    # Patterns that indicate a class slipped past gaia-token migration.
    raw_patterns = [
      /\b(bg-(?:white|black|(?:#{neutrals})-\d+))\b/,
      /\b(text-(?:white|(?:#{neutrals})-\d+|emerald-(?:400|500|600|700|800|900)))\b/,
      /\b(border-(?:(?:#{neutrals})-\d+|emerald-(?:700|800|900)))\b/
    ]

    # Decorative / brand allowlist — these are intentional and not migrated.
    allowlist = [
      "bg-emerald-500/10",  # login submit brand glow
      "bg-emerald-500/20",  # brand glow (parcel of the /10 pair)
      "bg-emerald-500",     # brand pulse / animate-ping accents
      "border-emerald-500/20" # spinner ring
    ]

    violations = []
    scanned = 0
    paths.each do |path|
      next unless path.extname == ".rb"
      next unless path.exist?

      scanned += 1
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

    # [DOC-T.64] Population lantern. A green verdict is a claim about the files that
    # were READ — and a mistyped or space-separated `COMPONENTS=` yields a Pathname
    # that is neither a directory nor an existing file, so the loop above scanned
    # nothing and the ✓ below would attest an empty set. The comment at the head of
    # this file has described that hole since it was written; describing is not
    # closing. Same shape as the `expect(scanned_files.size).to be > N` floor every
    # spec/quality gate carries.
    if scanned.zero?
      abort "✗ gaia:lint_tokens — НУЛЬ файлів прочитано (scope: #{ENV['COMPONENTS'] || 'app/views/shared/'}). " \
            "Вердикту немає: перевірка не бігла. COMPONENTS= бере ОДИН шлях."
    end

    if violations.empty?
      puts "✓ gaia:lint_tokens — no raw Tailwind colour utilities detected (#{scanned} files scanned)"
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
