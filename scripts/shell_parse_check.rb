#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# =============================================================================
# [OPS.28] shell_parse_check — `bash -n` over every shell artifact in the tree,
# including the shell that lives INSIDE terraform heredocs.
# =============================================================================
#
# WHY THIS EXISTS. The shell that actually runs the deploy is parsed by nothing:
# `actionlint` judges `run:` blocks in `.github/workflows/**` and nothing else,
# rubocop is Ruby, and terraform `validate` checks HCL — the heredoc body is an
# opaque string to it. So `bin/docker-entrypoint` (every container), the
# `.kamal/hooks/pre-build` (step ZERO of `kamal deploy`), `terraform/bootstrap.sh`
# and the two GCE startup scripts had exactly one reader: the author's attention.
# Their FIRST run is deploy day, which is the class "an artifact a human executes
# is code without a compiler" — no gate, and the runtime arrives at the worst
# possible moment.
#
# 🔒 DECLARED CEILING — read this before trusting a green.
#   * It judges SYNTAX, never SEMANTICS. `bash -n` cannot see an unset variable, a
#     wrong path, a swallowed error (`|| true`), a command that does not exist on
#     the target host, or logic that is simply wrong. A green here says "bash can
#     parse this", nothing more.
#   * It is a RATCHET, not a detector. The live yield when it was built was ZERO
#     (measured: every subject parsed). It exists so the NEXT edit cannot ship a
#     file that will not parse — because that edit's first execution is the one
#     that matters. A gate whose yield is zero and whose false-positive rate is
#     zero BY CONSTRUCTION (a file either parses or it does not) is the rare case
#     where a ratchet is honest; do not read its green as "the shell is correct".
#   * `sh`-shebang files are parsed by BASH, which is a superset. A construct
#     bash accepts and dash rejects passes here. Two such files exist today
#     (`bin/dev`, some `.kamal/hooks/*.sample`); if that ever matters, the fix is
#     `dash -n` for those, not widening this.
#   * Terraform interpolations (`${…}`) are replaced by a placeholder token before
#     parsing, so a syntax error INSIDE an interpolation is invisible. That half
#     belongs to `terraform validate`, which does read it.
#
# HOW SUBJECTS ARE FOUND — deliberately DISCOVERED, never listed.
#   A hard-coded list is a second home that rots: [OPS.28] itself recorded "20
#   shell files + 2 heredocs", and the measurement that built this gate found 27
#   files, because `bin/docker-entrypoint` is `#!/bin/bash -e` and a shebang regex
#   anchored at end-of-line does not match it.
#   1. every git-tracked path ending in `.sh`;
#   2. every git-tracked path whose FIRST LINE is a shell shebang (args allowed);
#   3. every heredoc in `terraform/*.tf` whose body starts with a shebang — the
#      shebang IS the discriminator, which is why the neighbouring `COAP_ENV`
#      heredoc (an env-file, no shebang) is correctly out of scope without any
#      name-based exception.
#
# Exit 0 = every subject parses. Exit 1 = at least one does not (named), or the
# subject set fell below SUBJECT_FLOOR — a pin on an empty set is green forever,
# so an empty discovery is a FAILURE here, not a pass.

require "open3"
require "tmpdir"

REPO_ROOT = File.expand_path("..", __dir__)

# Floor, not a count: the set grows with the tree, and a number in prose would rot
# the way [OPS.28]'s did. It exists only to catch a broken DISCOVERY (a `git`
# invocation that returns nothing still parses "every" subject successfully).
SUBJECT_FLOOR = 20

# 🔴 The `env` form is the trap, and the selftest is what caught it. A naive
# `\A#!\s*\S*\b(?:bash|sh|…)\b` cannot match `#!/usr/bin/env sh`: `\S*` stops at the
# space, so the interpreter name is never reached — and `#!/usr/bin/env bash` is the
# most common modern spelling, so the gate would have been silently NARROWER than its
# own docstring while reporting a confident subject count. Hence: optional path,
# optional `env`, then the interpreter.
SHEBANG = %r{\A\#!\s*(?:\S*/)?(?:env\s+)?(?:ba|z|k|da)?sh\b}

def git_files
  out, _err, status = Open3.capture3("git", "-C", REPO_ROOT, "ls-files", "-z")
  abort "shell_parse_check: `git ls-files` failed — not a repo?" unless status.success?
  out.split("\0").reject(&:empty?)
end

def shell_file?(path)
  return true if path.end_with?(".sh")

  full = File.join(REPO_ROOT, path)
  return false unless File.file?(full)
  # Read only the first line: the tree carries binaries (fonts, images, STL) and
  # slurping them would be both slow and pointless.
  first = File.open(full, "rb") { |f| f.readline(chomp: true) rescue "" }
  first.match?(SHEBANG)
rescue ArgumentError, EOFError, Errno::EACCES
  false # binary garbage in the first line, or empty file — not shell
end

# A terraform `<<-TAG … TAG` body, dedented, with `${…}` neutralised. Returns
# [label, source] pairs for every heredoc whose body starts with a shebang.
def terraform_heredocs
  Dir[File.join(REPO_ROOT, "terraform", "*.tf")].sort.flat_map do |tf|
    File.read(tf).scan(/<<-?([A-Z][A-Z0-9_]*)\n(.*?)\n[ \t]*\1\b/m).filter_map do |tag, body|
      dedented = dedent(body)
      next unless dedented.lstrip.start_with?("#!")

      label = "#{File.basename(tf)} heredoc <<#{tag}"
      [ label, neutralise_interpolations(dedented) ]
    end
  end
end

# Terraform renders `$${X}` as a LITERAL `${X}` (a real shell expansion at run
# time) and `${X}` as an interpolated value we cannot know. So the escape must
# SURVIVE as shell, and only the true interpolation is neutralised.
#
# 🔴 ONE pass with an alternation, deliberately NOT a sentinel round-trip. The
# first draft swapped `$${` to a sentinel byte and back, and it was wrong twice:
# such a swap corrupts any body that already contains the sentinel, and the byte
# itself leaked into this file — git classified a Ruby script as BINARY, which is
# how it was caught. ⚠️ The second draft then emitted `${}` for the escape branch
# (an outer heredoc ate the interpolation while the code was being written), which
# is INVALID shell — and the gate stayed GREEN, because no live heredoc uses `$${`
# today. That false green is exactly why `--selftest` below pins both branches:
# a transform whose only witness is the corpus is untested wherever the corpus is
# silent.
def neutralise_interpolations(body)
  body.gsub(/\$\$\{([^}]*)\}|\$\{[^}]*\}/) do
    escaped = Regexp.last_match(1)
    escaped ? "${#{escaped}}" : "TF_INTERPOLATION"
  end
end

def dedent(body)
  lines = body.lines
  indents = lines.reject { |l| l.strip.empty? }.map { |l| l[/\A[ \t]*/].length }
  cut = indents.min || 0
  lines.map { |l| l.strip.empty? ? l : l[cut..] }.join
end

def parse_ok?(source)
  Dir.mktmpdir("shell_parse") do |dir|
    f = File.join(dir, "subject.sh")
    File.write(f, source)
    _out, err, status = Open3.capture3("bash", "-n", f)
    return [ status.success?, err.to_s.strip.gsub(f, "<subject>") ]
  end
end

# --selftest — pins the two transforms the CORPUS cannot witness today.
# Both were silently broken at some point while this file was being written, and
# both stayed green over the live tree: no heredoc uses `$${`, and every heredoc
# happens to be indented uniformly. A transform tested only by "the corpus still
# passes" is untested exactly where the corpus is silent.
def selftest
  cases = [
    [ "escape survives as shell", -> { neutralise_interpolations('echo "$${HOME}/x"') },
      'echo "${HOME}/x"' ],
    [ "interpolation neutralised", -> { neutralise_interpolations('img=${var.coap_daemon_image}') },
      "img=TF_INTERPOLATION" ],
    [ "both in one line", -> { neutralise_interpolations('a=${var.x}; b=$${Y}') },
      "a=TF_INTERPOLATION; b=${Y}" ],
    [ "no-op when neither present", -> { neutralise_interpolations("echo plain $HOME") },
      "echo plain $HOME" ],
    [ "dedent strips common indent only", -> { dedent("    a\n      b\n") }, "a\n  b\n" ],
    [ "dedent keeps blank lines", -> { dedent("    a\n\n    b\n") }, "a\n\n b\n".sub(" b", "b") ],
    [ "shebang with args is shell", -> { SHEBANG.match?("#!/bin/bash -e").to_s }, "true" ],
    [ "env-shebang is shell", -> { SHEBANG.match?("#!/usr/bin/env sh").to_s }, "true" ],
    [ "env-file first line is NOT shell", -> { SHEBANG.match?("RAILS_ENV=production").to_s }, "false" ],
    [ "ruby shebang is NOT shell", -> { SHEBANG.match?("#!/usr/bin/env ruby").to_s }, "false" ]
  ]
  bad = cases.filter_map do |name, run, want|
    got = run.call
    got == want ? nil : "  ✗ #{name}\n      want: #{want.inspect}\n      got:  #{got.inspect}"
  end
  if bad.empty?
    puts "✓ selftest: #{cases.size}/#{cases.size}"
    exit 0
  end
  warn "✗ selftest failures (#{bad.size}/#{cases.size}):"
  bad.each { |b| warn b }
  exit 1
end

selftest if ARGV.include?("--selftest")

subjects = git_files.select { |p| shell_file?(p) }
                    .map { |p| [ p, File.read(File.join(REPO_ROOT, p)) ] }
subjects += terraform_heredocs

failures = subjects.filter_map do |label, source|
  ok, err = parse_ok?(source)
  ok ? nil : [ label, err ]
end

puts "shell_parse_check — #{subjects.size} subject(s): " \
     "#{subjects.count { |l, _| !l.include?('heredoc') }} file(s) + " \
     "#{subjects.count { |l, _| l.include?('heredoc') }} terraform heredoc(s)"

if subjects.size < SUBJECT_FLOOR
  warn "✗ subject set collapsed to #{subjects.size} (floor #{SUBJECT_FLOOR}) — discovery is broken, " \
       "not the tree. A green over an empty set attests nothing."
  exit 1
end

if failures.empty?
  puts "✓ every shell subject parses (`bash -n`)"
  exit 0
end

warn "✗ shell subject(s) that do NOT parse (#{failures.size}):"
failures.each { |label, err| warn "  · #{label}\n      #{err.lines.first(3).join('      ')}" }
warn "\nThese run on deploy day with no other reader — see the header of #{__FILE__}."
exit 1
