# frozen_string_literal: true

# One-shot migration helper: 00_07 meta-line `**PN** · executor · → ref`
#   → `**PN** · WHO · STAGE · → ref` (two orthogonal axes; 00_06/00_07 standard).
#
#   ruby scripts/stage_migrate.rb --propose            # read-only: print table + write /tmp/stage_map.tsv
#   ruby scripts/stage_migrate.rb --apply /tmp/stage_map.tsv   # rewrite meta-lines from the (reviewed) TSV
#
# WHO   = 🤖 / 👤 (combo 🤖+👤, leading first)
# STAGE = ⚪ not-started · 🟡 in-progress · 🟢 done-inert · 🔗 blocked · 🌿 far-horizon
#
# --propose only HEURISTICALLY guesses STAGE (signals printed so a human re-audits,
# esp. 🔗 = still-blocked? and 🌿 = far-horizon?). The TSV is reviewed BEFORE --apply.
# --apply rewrites ONLY the single meta-line per item (no body edits) → no glue risk.

PATH = File.expand_path("../docs/00_07_Action_Plan_Tracker.md", __dir__)
ITEM_HEAD = /^####\s+(?:[✅\p{So}\p{Sk}\u{FE0F}]+\s+)*([A-Z][A-Za-z0-9]*[.\-][0-9A-Za-z.\-]+)\s+[—-]\s+(.+?)\s*$/
META = /^- \*\*(P[0-3])\*\*/
REGISTRY = /^## (?:§|🔀)/
SKIP = /^## (?:🎯|🚦|📌|🗄️)/

WHO_EMO   = { "🤖" => "🤖", "👤" => "👤" }.freeze
BENCH_KW  = /bench|кремн|silicon|REVB|SWD|HAL-глю|HAL_FLASH|on-?chip|фліп|flip|плат[аіу]|залізі|option byte|PPK2|JS220|термокамер|пайк|осцил/i
ACTIV_KW  = /провіж|provision|deploy|деплой|імпорт|import|запустити|заповнити|verify|верифік|підтвердити|створити (?:Gnosis|Safe)|замінити .*ключ|swap|активува|налаштувати|RAILS_ALLOWED|secret|gsutil|підставити|замінити `0x0000|provision/i
BLOCK_KW  = /залежить|чекає (?:іншої|на)|blocked|заблоков|після (?:CCM|FW\.|UNI\.|HW\.|BIZ\.)|DAO|founder-рішенн|ground-truth|калібруванн|partner|партнер/i
HORIZON_KW = /post-?TRL|Post-?TRL|TRL [789]\+|TRL 7\+|far-horizon|North-Star|Series D|moonshot|Gen 3|TRL 9/i

# Re-audited overrides (verify-by-reading, 2026-06-14) — where the heuristic is wrong.
# Esp. "blocked" that is actually done-inert (host-done, awaiting bench/FW.2/FW.4) or unblocked.
OVERRIDES = {
  "FW.2"=>[ "👤", "🟢" ],     "FW.20"=>[ "👤", "🟢" ],    # already cemented — keep consistent
  "FW.4"=>[ "👤", "🟢" ],     "FW.8"=>[ "👤", "🟢" ],     "FW.17"=>[ "👤", "🟢" ],
  "FW.27"=>[ "🤖", "🟢" ],    "FW.42"=>[ "🤖", "🟢" ],    "ARCH.40"=>[ "🤖", "🟢" ],
  "ARCH.41"=>[ "👤", "🟢" ],  "SEC.12"=>[ "👤", "🟢" ],   "ARCH.35"=>[ "👤", "🟢" ],
  "BIZ.14"=>[ "🤖", "🟢" ],   "ARCH.34"=>[ "🤖", "⚪" ],   # ARCH.34 = named-next AI task, NOT blocked
  "S6.10"=>[ "🤖", "🔗" ],    "UNI.15"=>[ "👤+🤖", "🔗" ], "UNI.16"=>[ "👤", "🔗" ], "STK.3"=>[ "👤", "🔗" ],
  "HW.1"=>[ "👤", "⚪" ],      "UNI.9"=>[ "👤", "⚪" ],     # HW.1: license=precondition; UNI.9: false-🌿
  "BIZ.8"=>[ "👤", "⚪" ],                              # BIZ.6-✅=precondition; own quotes/NDA not started
  "SE050-MIGRATION"=>[ "🤖+👤", "🟡" ],                # real SE05x mechanics rewrite (not activation)
  "FW.31"=>[ "👤", "🟢" ],    "FW.50"=>[ "👤", "🟢" ],    "FW.55"=>[ "👤", "🟢" ], "FW.52"=>[ "👤", "🟢" ],
  "FW.54"=>[ "👤", "🟢" ],    "FW.56"=>[ "👤", "🟢" ],    "FW.46"=>[ "🤖+👤", "🟢" ], "FW.26"=>[ "🤖", "🟢" ],
  "FW.25"=>[ "🤖+👤", "🟢" ]                           # DSP+baseline done; open = optional upgrades only
}.freeze

def parse(lines)
  items = []
  cur = nil
  in_reg = false
  lines.each_with_index do |line, i|
    if line.start_with?("## ")
      items << cur if cur
      cur = nil
      in_reg = line.match?(REGISTRY) && !line.match?(SKIP)
      next
    end
    next unless in_reg
    if (m = line.match(ITEM_HEAD))
      items << cur if cur
      cur = { id: m[1], title: m[2], head_i: i, meta_i: nil, pn: nil, meta: nil, head_line: line, body: [] }
    elsif cur
      cur[:body] << [ i, line ]
      if cur[:meta_i].nil? && (pm = line.match(META))
        cur[:meta_i] = i
        cur[:pn] = pm[1]
        cur[:meta] = line
      end
    end
  end
  items << cur if cur
  items
end

def classify(it)
  return OVERRIDES[it[:id]] + [ "OVERRIDE (re-audit)" ] if OVERRIDES.key?(it[:id])
  meta = it[:meta] || ""
  body_text = it[:body].map { |_, l| l }.join
  head = it[:head_line] || ""

  # WHO — from the meta-line; fall back to checkbox bullets for 🔗/🟡-only metas.
  who = []
  who << "🤖" if meta.include?("🤖")
  who << "👤" if meta.include?("👤")
  if who.empty?
    cb = it[:body].select { |_, l| l =~ /^\s*-?\s*[·]?\s*\[ \]/ || l.include?("[ ]") }.map { |_, l| l }.join
    who << "🤖" if cb.include?("🤖")
    who << "👤" if cb.include?("👤")
  end
  who = [ "👤" ] if who.empty?            # safest default — owner
  who_s = who.sort_by { |w| w == "🤖" ? 0 : 1 }.uniq.join("+")  # 🤖 leads if both? -> but keep leading=primary; refine in review

  # STAGE signals
  done = body_text.scan(/✅|\[x\]/i).size
  open = body_text.scan(/\[ \]/).size
  was_blocked = meta.include?("🔗")
  was_yellow  = meta.include?("🟡")
  is_horizon  = head.include?("🌿") || meta.include?("🌿") || body_text =~ HORIZON_KW
  open_lines  = it[:body].select { |_, l| l.include?("[ ]") }.map { |_, l| l }
  all_open_inert = open.positive? && open_lines.all? { |l| l =~ BENCH_KW || l =~ ACTIV_KW }
  blocked_sig = was_blocked || body_text =~ BLOCK_KW

  stage =
    if was_yellow then "🟢"                                   # founder's 🟡 = done-inert
    elsif was_blocked then "🔗"                               # RE-AUDIT: still blocked? (OVERRIDES fix the false ones)
    elsif is_horizon && done.zero? then "🌿"                  # post-TRL & nothing started
    elsif done.positive? && all_open_inert then "🟢"          # code done, only bench/activation (deploy/provision) left
    elsif done.positive? && open.positive? then "🟡"          # partial — real build remaining
    elsif done.positive? && open.zero? then "🟢"              # done but not archived (residual=optional)
    else "⚪"                                                  # only [ ], nothing built
    end

  sig = "done:#{done} open:#{open}"
  sig += " was🔗" if was_blocked
  sig += " was🟡" if was_yellow
  sig += " inert-open" if all_open_inert
  sig += " block-kw" if blocked_sig && !was_blocked
  sig += " horizon-kw" if is_horizon
  [ who_s, stage, sig ]
end

mode = ARGV[0]
lines = File.readlines(PATH)
items = parse(lines)

if mode == "--propose"
  tsv = []
  puts "%-14s %-9s → %-7s %-5s  %s" % %w[ID oldMeta WHO STAGE signals]
  puts "-" * 90
  items.each do |it|
    old = (it[:meta] || "")[/\*\*P[0-3]\*\* · ([^→]*?) ·/, 1]&.strip || "?"
    who, stage, sig = classify(it)
    puts "%-14s %-9s → %-7s %-5s  %s" % [ it[:id], old[0, 9], who, stage, sig ]
    tsv << "#{it[:id]}\t#{who}\t#{stage}\t#{old}\t#{sig}"
  end
  File.write("/tmp/stage_map.tsv", tsv.join("\n") + "\n")
  warn "\n#{items.size} items → /tmp/stage_map.tsv (review WHO+STAGE, then --apply)"
elsif mode == "--apply"
  map = {}
  File.readlines(ARGV[1]).each do |l|
    id, who, stage, = l.chomp.split("\t")
    map[id] = [ who, stage ] if id && who && stage
  end
  applied = 0
  items.each do |it|
    pair = map[it[:id]]
    next unless pair && it[:meta_i]
    who, stage = pair
    ref = it[:meta][/(· → .*)$/, 1]   # everything from `· → ` onward (canon-ref + any tail)
    abort "no ref in meta for #{it[:id]}: #{it[:meta].inspect}" unless ref
    lines[it[:meta_i]] = "- **#{it[:pn]}** · #{who} · #{stage} #{ref}\n"
    applied += 1
  end
  File.write(PATH, lines.join)
  warn "applied #{applied} meta-line rewrites"
else
  abort "usage: --propose | --apply <tsv>"
end
