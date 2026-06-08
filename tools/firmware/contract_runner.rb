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
# Protocol: reads {"cases":[[x,y,z,temp,acoustic,delta_t], ...]} from stdin,
# writes [[payload_byte, z_final], ...] (same order) as JSON to stdout.

require "json"
require_relative "../../firmware/bio_contracts/bio_contract"

cases = JSON.parse($stdin.read).fetch("cases")
results = cases.map do |x, y, z, temp, acoustic, delta_t|
  payload_byte, _x_final, _y_final, z_final =
    SilkenNet::BioContract.evaluate_and_pack(x, y, z, temp, acoustic, delta_t)
  [ payload_byte, z_final ]
end
$stdout.write(JSON.generate(results))
