# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [FW.57 F4] Isolated runner for the REAL firmware contract.
#
# firmware/bio_contracts/bio_contract.rb defines its OWN SilkenNet::Attractor,
# so it CANNOT be co-loaded with the backend SilkenNet::Attractor in one Ruby
# process. This script loads ONLY the firmware contract (no Rails, no Bundler —
# the contract is dependency-free) and runs it as a subprocess, so
# spec/services/silken_net/attractor_spec.rb can compare the REAL contract's
# output to the backend mirror DIRECTLY — instead of against a hand-copied
# `firmware_z` re-implementation (a 3rd kernel copy that can silently drift while
# both "parity" sides still agree). See 00_07 — FW.57.
#
# Protocol: reads {"cases":[[x,y,z,temp,acoustic,delta_t(,z_min,z_max)], ...]} from stdin,
# or {"ccm_cases":[pt_hex, ...]} for the CCM-era contract (FW.66 S4 — returns status bytes),
# writes [[payload_byte, z_final], ...] (same order) as JSON to stdout. [FW.8] z_min/z_max
# optional — absent ⇒ the contract defaults (CRITICAL_Z_MIN/MAX), as on the shipped build.

require "json"
require_relative "../../firmware/bio_contracts/metabolic_core"
require_relative "../../firmware/bio_contracts/bio_contract"
require_relative "../../firmware/bio_contracts/ccm_contract"

input = JSON.parse($stdin.read)

# [FW.66 S4] Контракт CCM-ери: {"ccm_cases":["<14 байт plaintext hex>", ...]} → [status_byte, ...].
if (pts = input["ccm_cases"])
  $stdout.write(JSON.generate(pts.map { |hex| ccm_state([ hex ].pack("H*")) }))
  exit
end

cases = input.fetch("cases")
results = cases.map do |x, y, z, temp, acoustic, delta_t, *band|
  payload_byte, _x_final, _y_final, z_final =
    SilkenNet::BioContract.evaluate_and_pack(x, y, z, temp, acoustic, delta_t,
                                             SilkenNet::Attractor::NOMINAL_VCAP_MV, *band)
  [ payload_byte, z_final ]
end
$stdout.write(JSON.generate(results))
