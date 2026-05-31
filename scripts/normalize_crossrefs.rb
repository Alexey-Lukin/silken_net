#!/usr/bin/env ruby
# frozen_string_literal: true

#
# scripts/normalize_crossrefs.rb — звести ВСІ doc-id крос-рефи до ОДНОГО формату:
#   [`NN_NN`](Doc) — Title            (whole-doc; title зберігається з повного імені)
#   [`NN_NN §X`](Doc) descriptor      (section ref; §-частина у code-span, опис — у прозі)
#   [`NN_NN`](Doc)                     (bare inline whole-doc — просто backtick'и)
# Prose-фразові лінки (мітка без doc-id) лишаються. href НІКОЛИ не змінюється.
#
# Інваріанти (zero-loss): мультимножина href-ів і к-сть doc-лінків — до==після.
# Dry-run за замовч.; WRITE=1 застосовує.
#
# Usage: ruby scripts/normalize_crossrefs.rb [--show] ; WRITE=1 ruby … применить

SHOW  = ARGV.delete("--show")
WRITE = ENV["WRITE"] == "1"
root  = File.expand_path("..", __dir__)
files = Dir.glob(File.join(root, "docs", "[0-9][0-9]_[0-9][0-9]_*.md")).sort

LINK = /\[([^\]]*)\]\((\d\d_\d\d_[A-Za-z0-9_]+)(#[^)]*)?\)/
SEC  = /\A(§[0-9A-Za-zА-Яа-яІіЇїЄє.\-]+(?:\s*\+\s*§[0-9A-Za-zА-Яа-яІіЇїЄє.\-]+)*)\s*(.*)/m

# Returns the normalized label, or nil if already canonical / leave-as-is (prose).
def norm_label(label, id)
  l = label.strip
  # already canonical: code-span leading with `id` or `id §…` (extra prose outside OK)
  return nil if l =~ /\A`#{id}(\s+§[^`]*)?`/
  # prose-phrase: no doc-id token in the label (plain or escaped) → legit, leave
  return nil if l !~ /#{id}/ && l !~ /#{id[0, 2]}\\_#{id[3, 2]}/

  core = l.delete("`").gsub(/\\_/, "_").strip       # un-codespan + un-escape
  rest = core.sub(/\A#{id}[_ ]?/, "").strip         # drop the id + its `_`/space joiner
  if rest.empty?
    "`#{id}`"                                        # bare id → just backticks
  elsif rest.start_with?("§")
    sec, desc = rest.match(SEC)&.captures || [ rest, "" ]
    "`#{id} #{sec.strip}`#{desc.empty? ? '' : " #{desc.strip}"}"
  else
    title = rest.tr("_", " ").strip                  # full-name OR descriptive words
    "`#{id}` — #{title}"
  end
end

total_changed = 0
files.each do |path|
  text = File.read(path)
  in_fence = false
  changed = 0
  out = text.each_line.map do |line|
    if line.start_with?("```")
      in_fence = !in_fence
      next line
    end
    next line if in_fence

    line.gsub(LINK) do
      label, href, anchor = Regexp.last_match.captures
      id = href[0, 5]
      nl = norm_label(label, id)
      if nl && nl != label
        changed += 1
        "[#{nl}](#{href}#{anchor})"
      else
        Regexp.last_match[0]
      end
    end
  end.join

  next if changed.zero?

  # invariant: href multiset + link count unchanged
  hrefs_before = text.scan(LINK).map { |_, h, a| "#{h}#{a}" }.sort
  hrefs_after  = out.scan(LINK).map  { |_, h, a| "#{h}#{a}" }.sort
  if hrefs_before != hrefs_after
    warn "‼ #{File.basename(path)}: HREF MULTISET CHANGED — skipping (before #{hrefs_before.size}, after #{hrefs_after.size})"
    next
  end

  total_changed += changed
  base = File.basename(path)[0, 5]
  puts format("  %-6s %3d links normalized", base, changed)
  if SHOW
    text.each_line.zip(out.each_line) { |a, b| puts "    - #{a.strip}\n    + #{b.strip}\n" if a != b }
  end
  File.write(path, out) if WRITE
end

puts "\n── #{WRITE ? 'WROTE' : 'dry-run'}: #{total_changed} doc-id links → canonical code-span form across #{files.size} docs"
puts "   (run with --show to see per-line diffs; WRITE=1 to apply)" unless WRITE
