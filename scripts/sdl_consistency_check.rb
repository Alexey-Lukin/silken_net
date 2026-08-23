#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# SDL-consistency gate (CI: ci.yml). Catches the INF.17 class of dead paths
# at the manifest level:
#   1. a service declared in `services:` but absent from `deployment:` is
#      silently never leased by an Akash provider;
#   2. a deployment entry pointing at a missing compute profile;
#   3. the static SDL and the terraform template drifting apart in their
#      service sets (the tpl once lost the coap service this exact way).
#
# The .tpl is not valid YAML (terraform templatefile syntax), so directives
# and ${var} placeholders are stripped before parsing — this doubles as the
# only parse-validation the template gets.
#
# ✅ MUTATION-VERIFIED 2026-08-23, all three invariants.
# 🔴 Invariant 3 needed an ISOLATED mutation, and that is the lesson worth the line:
#    dropping coap from the tpl's `deployment:` alone was caught by invariant 1 FIRST
#    ("services != deployment" *within* the tpl), which would have falsely credited 3.
#    Removing coap from the tpl ENTIRELY satisfies 1 and leaves only the cross-manifest
#    comparison to fire — it did, with a distinct message ("service sets diverge").
#    Two mechanisms on one input mask each other: mutate one at a time.

require "yaml"

STATIC = "deploy/akash/deploy.yaml"
TPL    = "deploy/akash/deploy.yaml.tpl"

def load_tpl(path)
  text = File.read(path)
  text = text.gsub(/^%\{[^}]*\}/, "")      # leading %{ if … } / %{ endif ~ } directives
  text = text.gsub(/\$\{[^}]+\}/, "TPLVAR") # ${var} placeholders → parseable literal
  YAML.safe_load(text, aliases: true)
end

failures = []

def check_sdl(name, sdl, failures)
  services   = (sdl["services"] || {}).keys.sort
  deployment = (sdl["deployment"] || {}).keys.sort
  profiles   = (sdl.dig("profiles", "compute") || {}).keys.sort

  unless services == deployment
    failures << "#{name}: services #{services} != deployment #{deployment} — " \
                "a service missing from deployment: is never leased"
  end

  (sdl["deployment"] || {}).each do |svc, placements|
    placements.each_value do |spec|
      profile = spec["profile"]
      unless profiles.include?(profile)
        failures << "#{name}: deployment.#{svc} references missing compute profile #{profile.inspect}"
      end
    end
  end

  services
end

static_services = check_sdl(STATIC, YAML.safe_load_file(STATIC), failures)
tpl_services    = check_sdl(TPL, load_tpl(TPL), failures)

unless static_services == tpl_services
  failures << "service sets diverge: #{STATIC} #{static_services} vs #{TPL} #{tpl_services}"
end

if failures.empty?
  puts "✓ SDL consistency: #{static_services.join(', ')} identical in services/deployment across both manifests"
else
  puts "SDL CONSISTENCY FAILED:"
  failures.each { |f| puts "  ✗ #{f}" }
  exit 1
end
