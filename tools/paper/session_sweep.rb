#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Session-corpus sweep — the instrument of the second window of §4 in
# docs/protocols/paper/agent_self_deception_taxonomy.md [UNI.3].
#
#   ruby tools/paper/session_sweep.rb run --dir DIR --exclude UUID[,UUID…] --out OUT [--sample N]
#   ruby tools/paper/session_sweep.rb --selftest
#
# Reads the top-level *.jsonl transcripts of ONE project directory — sub-agent transcripts live in
# sub-directories and are not read — and drops the sessions named by --exclude: the session that runs a
# sweep writes the families' own vocabulary, so counting it would count the instrument. Each assistant
# message splits into two units: PROSE (content blocks of type text: what the agent says) and WRITES
# (string inputs of tool_use blocks: what the agent records into files, commits and memory). A family is
# one regular expression over one unit; a hit is a block it matches at least once.
#
# Writes three things into OUT:
#   manifest.json — every input file with sha256, bytes, first and last timestamp: the corpus fingerprint,
#                   the part of a run that is committed, since the harness deletes old transcripts (after 30 days
#                   by default, which is how window 1's corpus was lost; raised to 365 days in the harness settings
#                   on 2026-11-08, the founder's call) — still a deadline, so the measured window is also frozen as
#                   a private copy outside the repository;
#   counts.json   — per family: blocks matched in each unit, plus the unit totals;
#   samples/      — up to N matched blocks per family, seeded, with context: private text, read by hand
#                   to measure precision, and never committed.
#
# Declared ceilings — what a run does NOT give:
#   · precision: a count is a count of blocks that MATCH, not of events that happened; precision comes
#     only from reading the samples, and recall is not measured at all;
#   · comparability with the paper's first window: its regular expressions were not preserved, the
#     transcript format has changed since (it now carries service records, so «events» are not the same
#     unit), and these families are rebuilt from the paper's prose — a second point, not a re-measurement;
#   · a family written in the corpus's two working languages still misses paraphrase; the controls below
#     prove that each family can fire, not that it fires on every phrasing.

require "json"
require "digest"
require "fileutils"

module SessionSweep
  # Ruby's \w is ASCII-only, so it never matches a Cyrillic letter: families use \p{L} instead (lint below).
  FAMILIES = {
    "relapse" => {
      unit: :prose, re: /рецидив|relaps/i,
      pos: [ "це рецидив того самого класу", "a relapse of the rule" ], neg: [ "рекурсія того самого виклику" ]
    },
    "carrier_fired" => {
      unit: :prose,
      re: /(?:гейт|хук|носі[йяює]|guard|gate|hook)\p{L}*[^\n]{0,60}?(?:спійма|злови|caught)|(?:спійма|злови|caught)\p{L}*[^\n]{0,60}?(?:гейт|хук|носі[йяює]|guard|gate|hook)/i,
      pos: [ "гейт спіймав мене на цьому", "the hook caught the stray glob", "спіймав це хук" ], neg: [ "гейт зелений" ]
    },
    "form_held" => {
      unit: :prose, re: /форм\p{L}{0,4}[^\n]{0,40}?(?:вистоя|витрима)|\bform[^\n]{0,40}?\b(?:held|survived)\b/i,
      pos: [ "приписана форма вистояла", "the prescribed form held" ], neg: [ "форма впала на першому прогоні" ]
    },
    "false_alarm" => {
      unit: :prose,
      re: /хибн\p{L}* (?:тривог|сполох)|(?:тривог|сполох)\p{L}* (?:була |виявил\p{L}* )?(?:хибн|даремн)|даремн\p{L}* (?:тривог|сполох)|бив\p{L}* на сполох|знім\p{L}* (?:свою |власну )?(?:хибну )?тривог|false alarm/i,
      pos: [ "це була хибна тривога", "my false alarm", "бив на сполох даремно" ], neg: [ "хибний позитив гейта" ]
    },
    "missed" => {
      unit: :prose,
      re: /прогледі\p{L}*|недогледі\p{L}*|проґави\p{L}*|пропусти(?:в|ла|ли) (?:справжн|реальн|ваду|дефект|баг|клас|сусід|випадок)|не поміти(?:в|ла|ли)|мій промах|\bI missed\b|missed (?:a |the )?(?:real|genuine)/i,
      pos: [ "я прогледів справжню ваду", "missed a real defect", "я не помітив сусіда", "мій промах" ], neg: [ "пропустив коміт", "пропустив тест" ]
    }
  }.freeze

  module_function

  def units(record)
    msg = record["message"]
    return [ [], [] ] unless record["type"] == "assistant" && msg.is_a?(Hash) && msg["content"].is_a?(Array)
    prose = msg["content"].filter_map { |c| c["text"] if c.is_a?(Hash) && c["type"] == "text" && c["text"].is_a?(String) }
    writes = msg["content"].flat_map { |c| c.is_a?(Hash) && c["type"] == "tool_use" ? strings(c["input"]) : [] }
    [ prose, writes ]
  end

  def strings(v) = v.is_a?(String) ? [ v ] : v.is_a?(Hash) ? v.values.flat_map { strings(_1) } : v.is_a?(Array) ? v.flat_map { strings(_1) } : []

  def run(dir:, exclude:, out:, sample:)
    files = Dir[File.join(dir, "*.jsonl")].sort.reject { |f| exclude.include?(File.basename(f, ".jsonl")) }
    abort "run: no transcripts in #{dir}" if files.empty?
    totals = Hash.new(0)
    hits = FAMILIES.keys.to_h { |k| [ k, { prose: [], writes: [] } ] }
    manifest = files.map do |f|
      first = last = nil
      File.foreach(f) do |line|
        rec = JSON.parse(line) rescue next
        ts = rec["timestamp"]
        first ||= ts if ts
        last = ts if ts
        totals[:records] += 1
        prose, writes = units(rec)
        totals[:prose] += prose.size
        totals[:writes] += writes.size
        { prose: prose, writes: writes }.each do |unit, blocks|
          blocks.each do |b|
            FAMILIES.each { |name, fam| hits[name][unit] << [ File.basename(f, ".jsonl"), ts, b ] if b.match?(fam[:re]) }
          end
        end
      end
      { "file" => File.basename(f), "sha256" => Digest::SHA256.file(f).hexdigest, "bytes" => File.size(f), "first" => first, "last" => last }
    end
    FileUtils.mkdir_p(File.join(out, "samples"))
    window = manifest.flat_map { [ _1["first"], _1["last"] ] }.compact.minmax
    File.write(File.join(out, "manifest.json"), JSON.pretty_generate({ "sessions" => manifest.size, "excluded" => exclude, "window" => window, "files" => manifest }))
    counts = FAMILIES.to_h { |name, fam| [ name, { "unit" => fam[:unit].to_s, "prose" => hits[name][:prose].size, "writes" => hits[name][:writes].size } ] }
    File.write(File.join(out, "counts.json"), JSON.pretty_generate({ "sessions" => manifest.size, "window" => window, "records" => totals[:records],
                                                                    "prose_blocks" => totals[:prose], "write_strings" => totals[:writes], "families" => counts }))
    rng = Random.new(20_261_108)
    FAMILIES.each_key { |name| %i[prose writes].each { |unit| write_sample(out, name, unit, hits[name][unit], sample, rng) } }
    puts JSON.pretty_generate(JSON.parse(File.read(File.join(out, "counts.json"))))
  end

  def write_sample(out, name, unit, pool, sample, rng)
    re = FAMILIES[name][:re]
    File.open(File.join(out, "samples", "#{name}.#{unit}.txt"), "w") do |io|
        pool.sample([ sample, pool.size ].min, random: rng).each_with_index do |(sid, ts, text), i|
          m = text.match(re)
          io.puts "#### #{i + 1} · #{sid} · #{ts}", text[[ m.begin(0) - 300, 0 ].max, 700], ""
        end
    end
  end

  def selftest
    fails = 0
    t = ->(name, ok) { puts "#{ok ? 'ok  ' : 'FAIL'} #{name}"; fails += 1 unless ok }
    FAMILIES.each do |name, fam|
      t.call("#{name}: no \\w (ASCII-only in Ruby, blind to Cyrillic)", !fam[:re].source.include?('\w'))
      t.call("#{name}: every positive control matches", fam[:pos].all? { _1.match?(fam[:re]) })
      t.call("#{name}: no negative control matches", fam[:neg].none? { _1.match?(fam[:re]) })
    end
    rec = { "type" => "assistant", "message" => { "content" => [ { "type" => "text", "text" => "a" }, { "type" => "thinking", "thinking" => "b" },
                                                                 { "type" => "tool_use", "input" => { "x" => [ "c", { "y" => "d" } ] } } ] } }
    t.call("units: text blocks are prose, nested tool inputs are writes, thinking is neither", units(rec) == [ [ "a" ], %w[c d] ])
    t.call("units: a user record yields nothing", units({ "type" => "user", "message" => { "content" => [ { "type" => "text", "text" => "a" } ] } }) == [ [], [] ])
    puts(fails.zero? ? "session_sweep --selftest: OK" : "session_sweep --selftest: #{fails} FAILED")
    exit(fails.zero? ? 0 : 1)
  end
end

if $PROGRAM_NAME == __FILE__
  case ARGV.shift
  when "--selftest" then SessionSweep.selftest
  when "run"
    opts = ARGV.each_slice(2).to_h
    abort "usage: run --dir DIR --exclude UUID[,UUID…] --out OUT [--sample N]" unless opts["--dir"] && opts["--out"]
    SessionSweep.run(dir: opts["--dir"], exclude: opts.fetch("--exclude", "").split(","), out: opts["--out"], sample: Integer(opts.fetch("--sample", "15")))
  else abort "usage: run … | --selftest"
  end
end
