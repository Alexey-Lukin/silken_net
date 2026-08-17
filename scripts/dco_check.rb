#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [UNI.20] DCO sign-off gate for INBOUND pull requests (CI `dco.yml`).
#
# The project is AGPL and expects inbound code from universities/students
# (`CONTRIBUTING.md` §DCO already asks for `git commit -s`) — but nothing
# ENFORCED it: a PR without a `Signed-off-by` trailer merged silently, so the
# copyright-origin certification the AGPL posture leans on (00_01 §8) existed
# as a request, not a gate. This is that gate. DCO > CLA here is a ratified
# decision (CNCF recommendation, OpenInfra CLA→DCO 2025, Nextcloud-AGPL
# precedent) — rationale + the two honest caveats (university thesis/grant IP,
# dual-license tension) live in `docs/protocols/business/oss_web3_standards.md`
# §4, state in `00_07` UNI.20.
#
# WHY hand-rolled instead of the `dcoapp/app` GitHub App: a third-party app
# needs an org-level install with write scope on a public repo, and its default
# author-match rule is exactly what breaks here (below). ~90 lines of stdlib
# Ruby is SHA-pin-free, locally runnable, and unit-testable — the same trade
# the repo already made for its other standalone guards.
#
# 🔴 THE NON-OBVIOUS PART — why bot authors are exempt (verified, not assumed):
# Dependabot DOES sign its commits, but with a MISMATCHED identity —
#   author     dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>
#   sign-off   Signed-off-by: dependabot[bot] <support@github.com>
# So a presence-only check passes Dependabot while proving nothing, and a
# strict author-match check (the `dcoapp` default, and the semantically correct
# one — you certify YOUR OWN contribution) fails EVERY Dependabot PR. This repo
# runs weekly Dependabot across five ecosystems, so that would have jammed the
# whole dependency queue on day one. Resolution: keep the strict author-match
# for humans, exempt `[bot]` authors explicitly. Bots do not hold copyright, so
# there is no origin to certify — the exemption is principled, not a workaround.
#
# Scope note: this gates PULL REQUESTS. The maintainer's authorized direct
# pushes to `main` never pass through a PR and are not checked — DCO governs
# INBOUND contribution, which is what UNI.20 is about.
#
# Declared ceiling — what a green run does NOT claim. The sentence enforced here
# is exactly one: "every non-bot commit in range carries a Signed-off-by whose
# EMAIL equals the commit's own author or committer". Everything else the DCO
# stands for rests on the contributor, not on this script:
#   · It cannot see WHO TYPED THE COMMAND. A git object holds tree, parents,
#     author, committer and message; no field distinguishes a person from
#     tooling running under their identity. `CONTRIBUTING.md` therefore states
#     "an AI never signs off" as an obligation on the contributor, not as
#     something checked here — and it says so in those words. Signatures buy a
#     different property (key ownership, anti-imposter), not this one.
#   · The NAME half of the trailer is ignored on purpose — only the address is
#     compared, so `Signed-off-by: Anyone <owner@example.com>` passes.
#   · Author OR committer is accepted, which is wider than "the author": a
#     rebaser's sign-off carries commits they did not write. That is deliberate
#     (see the rebase case in the spec), but it is wider than the prose reads.
#
# Pure Ruby (open3 stdlib, no Rails). Run from repo root:
#   ruby scripts/dco_check.rb                    # origin/main..HEAD
#   ruby scripts/dco_check.rb main..my-branch    # explicit range
# Exit 0 = every non-bot commit in range is signed off by its author.

require "open3"

module DcoCheck
  DEFAULT_RANGE = "origin/main..HEAD"
  SIGNOFF = /^\s*Signed-off-by:\s*(?<name>.+?)\s*<(?<email>[^>]+)>\s*$/i
  REMEDY = "git rebase --signoff <base>   (or `git commit -s` from the start)"

  module_function

  # A GitHub bot identity — `dependabot[bot]`, `github-actions[bot]`, … The
  # `[bot]` suffix is GitHub's own convention for App identities, so matching it
  # needs no per-bot allowlist to maintain (a list would rot; the suffix will not).
  def bot_author?(name, email)
    "#{name} #{email}".match?(/\[bot\]/i)
  end

  # Every `Signed-off-by:` trailer as [name, email] pairs. Deliberately scans the
  # whole message, not just the trailer block: `git commit -s` appends to the end,
  # but a rebase/amend can leave a blank line or a `Co-Authored-By` after it.
  def signoffs(body)
    body.to_s.lines.filter_map do |line|
      m = SIGNOFF.match(line)
      [ m[:name].strip, m[:email].strip.downcase ] if m
    end
  end

  # nil = compliant; a String = the violation. A sign-off must carry the identity
  # of the person who wrote the commit, matched on email (case-insensitive) against
  # the author OR the committer — the practical standard, tolerant of a rebase that
  # rewrites the committer while the author (the actual contributor) is preserved.
  def verdict(commit)
    return nil if bot_author?(commit[:author_name], commit[:author_email])

    signed = signoffs(commit[:body])
    short  = commit[:sha][0, 8]
    if signed.empty?
      return "#{short} `#{commit[:subject]}` — no Signed-off-by trailer " \
             "(author #{commit[:author_email]})"
    end

    owners = [ commit[:author_email], commit[:committer_email] ].compact.map(&:downcase)
    return nil if signed.any? { |(_n, email)| owners.include?(email) }

    "#{short} `#{commit[:subject]}` — Signed-off-by #{signed.map(&:last).join(', ')} " \
      "does not match the author (#{commit[:author_email]})"
  end

  # Commits in `range`, merge commits excluded (a merge is generated, not authored).
  # NUL-delimited so a multi-line body can never be mistaken for a field boundary.
  def commits(range)
    fmt = %w[%H %an %ae %ce %s %B].join("%x00")
    out, err, st = Open3.capture3("git", "log", "--no-merges", "--format=#{fmt}%x01", range)
    raise "git log #{range} failed: #{err.strip}" unless st.success?

    out.split("\x01").filter_map do |rec|
      sha, an, ae, ce, subject, body = rec.sub(/\A\n/, "").split("\x00", 6)
      next if sha.to_s.strip.empty?

      { sha: sha.strip, author_name: an, author_email: ae, committer_email: ce,
        subject: subject, body: body }
    end
  end

  def audit(range = DEFAULT_RANGE)
    all = commits(range)
    { range:, checked: all.reject { |c| bot_author?(c[:author_name], c[:author_email]) },
      skipped: all.select { |c| bot_author?(c[:author_name], c[:author_email]) },
      violations: all.filter_map { |c| verdict(c) } }
  end
end

if __FILE__ == $PROGRAM_NAME
  range = ARGV.find { |a| !a.start_with?("-") } || ENV["DCO_RANGE"] || DcoCheck::DEFAULT_RANGE
  r = DcoCheck.audit(range)

  puts "dco_check — range #{r[:range]}: #{r[:checked].size} commit(s) to certify" \
       "#{r[:skipped].empty? ? '' : ", #{r[:skipped].size} bot commit(s) exempt"}"

  if r[:violations].empty?
    puts "dco_check ✓ — every non-bot commit carries a matching Signed-off-by (UNI.20)."
    exit 0
  else
    warn "dco_check ✗ — DCO sign-off missing or mismatched (UNI.20):"
    r[:violations].each { |v| warn "  · #{v}" }
    warn "\nFix: #{DcoCheck::REMEDY}"
    warn "By signing off you certify the Developer Certificate of Origin 1.1 " \
         "(https://developercertificate.org/) — see CONTRIBUTING.md §DCO."
    exit 1
  end
end
