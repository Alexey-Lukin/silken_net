# frozen_string_literal: true

# Lints Phlex view components for raw Tailwind colour utilities that should
# be replaced with gaia design tokens (see docs/04_04 § 3.1).
#
# Reports per-file violations with line numbers. Exits 1 if any violations
# are found — wire into CI to keep the migration moving forward without
# regressions.
#
#   bundle exec rake gaia:lint_tokens                  # all components
#   COMPONENTS=app/views/components/wallets/ \
#     bundle exec rake gaia:lint_tokens                # subset
#
# Allowlist: see RAW_TAILWIND_ALLOWLIST below — small set of brand /
# decorative colours that are intentionally raw (e.g. `bg-emerald-500/10`
# for the brand-glow on the login button).
namespace :gaia do
  desc "Find raw Tailwind colour utilities in Phlex components (compliance check)"
  task lint_tokens: :environment do
    paths = (ENV["COMPONENTS"] || "app/views/components/").then do |p|
      Pathname.new(p).directory? ? Pathname.glob("#{p}/**/*.rb") : [ Pathname.new(p) ]
    end

    # Patterns that indicate a class slipped past gaia-token migration.
    raw_patterns = [
      /\bbg-(white|black|gray-\d+)\b/,
      /\btext-(white|gray-\d+|emerald-(400|500|600|700|800|900))\b/,
      /\bborder-(gray-\d+|emerald-(700|800|900))\b/
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
