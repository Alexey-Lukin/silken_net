# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "yaml"
require_relative "../support/repo_root"

# [S1.1] MECHANISM parity between the two deploy workflows.
#
# 🔴 The class, measured 2026-09-01 (`cdca0ec4`): fixing the deploy path fixed ONE of its two
# carriers. Nine `Deploy · Canopy` runs bought three mechanism steps — the ephemeral OS-Login
# SSH key, `docker network create kamal`, and the registry token on `proxy reboot` — and all
# three landed in `deploy.yml` alone. `deploy-production.yml` would have failed in exactly the
# same three ways, at the worst possible moment (a tagged release), and NOTHING could see it:
# each workflow is independently valid, `actionlint` never asks whether two deploys agree, and
# `env_fetch_declaration_spec` compared secret NAMES across their union and not their STEPS
# (past tense on purpose — the same session gave it a per-workflow step example; that is what
# now covers the one step THIS gate exempts, and the two must be read together).
# A shared surface with no shared home diverges silently and is discovered by EXECUTION.
#
# 🔒 DECLARED CEILING — this judges the step SEQUENCE and the env: KEYS of shared steps, never
# byte-equality and never `run:` BODIES (one declared exception since 2026-09-02: the membership example at
# the bottom reads the verify-secrets ASSIGNMENT lines, nothing else). ⚠️ That second half is the sharp one: gut the body of
# `docker network create kamal` while keeping the step name and this gate stays green — it sees
# LABELS, and most of what nine runs bought lives in the bodies. Calling it "mechanism parity"
# without this sentence overclaims, and it did until adversarial review of its own commit. Legitimately divergent, and deliberately NOT flagged:
#   · destination flags (`-d canopy`) inside `run:` bodies;
#   · the step-name suffix `to Canopy` ⊥ `to Production` (normalised below);
#   · `environment: production`, the `changes`/path-filter job, the release-vs-workflow_run
#     trigger, concurrency group, the COAP host Variable;
#   · the harden-runner egress POLICY (canopy `block` + measured allowlist ⊥ production `audit`
#     until ITS first real deploy — OPS.36); the step name carries the policy and is normalised;
#   · verify-secrets SEVERITY — canopy skips clean, production hard-fails. That asymmetry is
#     ratified, not drift;
#   · the money/signing quintet's SOURCE: both slots map the same KEYS since 2026-09-02 (canopy
#     has its own job role, OPS.37), but production reads Environment secrets and canopy reads
#     the `CANOPY_*` testnet twins — RHS, which `env_fetch_declaration_spec` judges per slot;
#   · comment prose — canopy carries the long measured rationale, production an abridged
#     pointer at it. A parity gate that read comments would fire on One-Home itself.
# ⚠️ It also cannot see anything that is NOT in the files: the GitHub Environment wait-timer is
# a repo setting, so `environment: production` is the only greppable trace of it.
#
# ✅ MUTATION-VERIFIED 2026-09-01, each in isolation, every file restored byte-identically
# (`cmp -s`), and the gate GREEN before and after each:
#   drop the OS-Login step from deploy-production.yml       → RED naming the step
#   drop `GCP_ARTIFACT_REGISTRY_KEY` from `Reboot Kamal Proxy` in one file → RED naming step+key
#   reorder two steps in one file                           → RED naming the sequence
RSpec.describe "deploy workflow mechanism parity [S1.1]" do # rubocop:disable RSpec/DescribeClass
  let(:workflows) { %w[.github/workflows/deploy.yml .github/workflows/deploy-production.yml] }
  # Steps of the job that actually ships the container. Keyed by workflow basename.
  let(:deploy_jobs) do
    workflows.to_h do |path|
      wf = YAML.safe_load(File.read(REPO_ROOT.join(path)), aliases: true)
      job = (wf["jobs"] || {}).values.grep(Hash)
                              .find { |j| j["name"].to_s.start_with?("Kamal Deploy (") }
      [ File.basename(path), Array(job&.dig("steps")).grep(Hash) ]
    end
  end

  # The ONE step whose env: legitimately diverges — BOTH ways: production carries the
  # money/signing quintet, canopy carries `CANOPY_REDIS_URL`. 🔴 The exemption is safe ONLY
  # because the sibling `env_fetch_declaration_spec` judges that step with PER-SLOT expected
  # sets (global+TLS on canopy, global+quintet+TLS on production, plus a negative that canopy
  # must NOT map the quintet). Until 2026-09-01 it did not — it demanded the global set on both
  # and deferred here, while this gate deferred there, so the quintet's and the TLS pair's
  # delivery were gated by NOTHING. ⛔ Do not widen this exemption without re-reading what the
  # sibling actually asserts today.
  # ⚠️ `start_with?` below, so any future step whose normalised name BEGINS with this joins the
  # exemption silently — keep the constant as specific as the real step name.
  # ⚠️ The NORMALISED name — `normalise` has already stripped the ` to Canopy`/` to Production`
  # suffix by the time this is compared. Writing the raw name here makes the exemption never
  # fire and the gate red on a correct tree; caught on this gate's own first run.
  def env_divergent_step = "Kamal Deploy"

  # `deploy.yml` names the slot in this one step; normalise so the SEQUENCE can be compared.
  # [OPS.36] The harden-runner step names its POLICY, and the policy legitimately differs per
  # slot (canopy `block` with a measured allowlist ⊥ production `audit` until its own first
  # deploy) — same mechanism, so the name is normalised to its policy-free form. Mutation
  # 2026-09-02: renaming production's step to anything else → RED naming the sequence.
  def normalise(name)
    name.sub(/\A(Kamal Deploy) to (Canopy|Production)\z/, '\1')
        .sub(/\AHarden runner \(egress (?:audit|block)\)\z/, "Harden runner (egress policy)")
  end


  it "reads two real deploy jobs with a non-trivial step list (non-vacuity)" do
    aggregate_failures do
      expect(deploy_jobs.keys.size).to eq(2)
      deploy_jobs.each do |file, steps|
        expect(steps.size).to be > 8, "#{file}: only #{steps.size} steps — parser drift?"
        expect(steps.map { |s| s["name"] }).to all(be_a(String))
      end
    end
  end

  it "runs the SAME mechanism steps, in the SAME order, on both slots" do
    canopy, production = deploy_jobs.values.map { |steps| steps.map { |s| normalise(s["name"].to_s) } }
    expect(production).to eq(canopy),
                          "deploy-production.yml and deploy.yml disagree on the deploy-job step " \
                          "sequence.\n  canopy:     #{canopy.inspect}\n  production: #{production.inspect}\n" \
                          "A step present on one slot only is a mechanism that debuts UNTESTED on the other."
  end

  it "gives every shared step the SAME env: keys (except the one that legitimately diverges)" do
    by_name = deploy_jobs.transform_values do |steps|
      steps.to_h { |s| [ normalise(s["name"].to_s), (s["env"] || {}).keys.sort ] }
    end
    canopy_name, production_name = by_name.keys
    shared = by_name[canopy_name].keys & by_name[production_name].keys
    expect(shared.size).to be > 5, "only #{shared.size} shared steps — normalisation drift?"

    mismatched = shared.reject { |n| n.start_with?(env_divergent_step) }
                       .filter_map do |n|
      a, b = by_name[canopy_name][n], by_name[production_name][n]
      next if a == b

      "#{n}: canopy #{(a - b).inspect.sub('[]', '—')} / production #{(b - a).inspect.sub('[]', '—')}"
    end
    expect(mismatched).to be_empty,
                          "shared deploy steps carry different env: keys — a step that works on one " \
                          "slot and not the other (the `GCP_ARTIFACT_REGISTRY_KEY`-on-`proxy reboot` " \
                          "shape, which cost five runs):\n  " + mismatched.join("\n  ")
  end

  # [OPS.37 review 2026-09-02] The verify-secrets CLASSIFICATION is the other shared surface,
  # and the one the ceiling above excluded. Measured that day: the canopy list re-derived what
  # `Web3NetworkGuard` demands of a signer at boot and applied it to canopy alone — production
  # still WARNED on the Solana quartet and the silent Polygon RPC the same guard refuses at job
  # boot. So this reads exactly the assignment lines and compares MEMBERSHIP modulo the
  # `CANOPY_` prefix. The declared remainder, `overlay_fatal`, is the set production may leave
  # unset (lazy read-sites) but the canopy overlay turns into a PRESENT placeholder the guard
  # refuses (key format · testnet chain scan) — boot-critical on canopy by construction of
  # `.kamal/secrets.canopy`, not by drift. Anything else that differs is drift.
  describe "verify-secrets membership modulo the CANOPY_ prefix" do
    let(:overlay_fatal) do
      %w[ETHEREUM_ANCHOR_PRIVATE_KEY ORACLE_CELO_PRIVATE_KEY ALCHEMY_ETHEREUM_RPC_URL SOLANA_RPC_URL CELO_RPC_URL]
    end
    let(:lists) do
      workflows.to_h do |path|
        wf  = YAML.safe_load(File.read(REPO_ROOT.join(path)), aliases: true)
        run = Array(wf.dig("jobs", "verify-secrets", "steps")).grep(Hash).map { |st| st["run"].to_s }
                                                            .find { |r| r.include?("BOOT_CRITICAL=") }
        [ File.basename(path), run.to_s.scan(/^\s*(BOOT_CRITICAL|JOB_CRITICAL|RUNTIME)="([^"]*)"/).to_h { |k, v| [ k, v.split ] } ]
      end
    end

    def strip(names) = names.map { |n| n.delete_prefix("CANOPY_") }

    it "gates on canopy (slot + job role) exactly what production gates, plus the overlay-fatal names" do
      canopy, production = lists.values_at("deploy.yml", "deploy-production.yml")
      aggregate_failures do
        expect(strip(canopy.fetch("BOOT_CRITICAL") + canopy.fetch("JOB_CRITICAL")).sort)
          .to eq((production.fetch("BOOT_CRITICAL") + overlay_fatal).sort)
        expect(strip(canopy.fetch("RUNTIME")).sort).to eq((production.fetch("RUNTIME") - overlay_fatal).sort)
      end
    end

    it "reads non-trivial lists from both workflows (non-vacuity)" do
      aggregate_failures do
        expect(lists.keys).to contain_exactly("deploy.yml", "deploy-production.yml")
        lists.each do |file, sets|
          expect(sets.fetch("BOOT_CRITICAL").size).to be > 10, "#{file}: BOOT_CRITICAL parsed to #{sets['BOOT_CRITICAL'].inspect}"
          expect(sets.fetch("RUNTIME").size).to be > 3, "#{file}: RUNTIME parsed to #{sets['RUNTIME'].inspect}"
        end
      end
    end
  end
end
