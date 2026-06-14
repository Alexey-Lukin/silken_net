#!/usr/bin/env ruby
# frozen_string_literal: true

#
# scripts/tracker_sort.rb — stable-sort `docs/00_07_Action_Plan_Tracker.md` `#### `
# item-blocks by priority (P0→P3) WITHIN each group.
#
# A "group" = the run of items under a `## ` or `### ` header (so §08 sub-groups
# 🌐 External Stakeholders / ⚖️ IP-Grants sort independently; the 🚦 Dashboard's
# `### ` buckets hold no `#### ` items → untouched; 📌/🗄️/DOC-T tables → untouched).
#
# An item-block = `#### …` through every following line until the next
# `####`/`###`/`## ` header — so a block carries its meta-line, Стан, residuals,
# trailing blank, AND any `##### ` children (HW.5.IS's CHEM/in-silico sub-lists).
#
# Stable: items of equal priority keep their current relative order (idempotent —
# re-running a sorted file is a no-op). Zero-loss by construction: the output is a
# pure permutation of input lines (asserted before write).

FILE = File.expand_path("../docs/00_07_Action_Plan_Tracker.md", __dir__)
lines = File.readlines(FILE)

def prio_of(block)
  block.each { |l| return Regexp.last_match(1).to_i if l =~ /\A- \*\*P([0-3])\*\*/ }
  warn "!! item-block without P-meta: #{block.first.strip}"
  9
end

def header?(l)
  l.start_with?("## ") || l.start_with?("### ")
end

out = []
buffer = [] # item-blocks (each an Array of lines) accumulating in the current group

flush = lambda do
  return if buffer.empty?

  buffer.each_with_index.sort_by { |blk, idx| [ prio_of(blk), idx ] }
        .each { |blk, _| out.concat(blk) }
  buffer = []
end

i = 0
n = lines.size
while i < n
  l = lines[i]
  if header?(l)
    flush.call
    out << l
    i += 1
  elsif l.start_with?("#### ")
    blk = [ l ]
    i += 1
    while i < n && !header?(lines[i]) && !lines[i].start_with?("#### ")
      blk << lines[i]
      i += 1
    end
    buffer << blk
  else
    flush.call # preamble before first item (buffer empty → no-op); never mid-group
    out << l
    i += 1
  end
end
flush.call

abort "ZERO-LOSS FAIL — output is not a permutation of input!" unless out.sort == lines.sort
File.write(FILE, out.join)
puts "Sorted #{lines.size} lines (zero-loss multiset verified)."
