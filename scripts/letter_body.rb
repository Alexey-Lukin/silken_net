#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Letter body assembler — the copy region of a letter file → the HTML body Gmail sends.
# Home of the method: skill `legal-business` §Доменні правила #13 (this script is its (а) half);
# ⚖️ founder 2026-11-07 — one generic assembler instead of a fresh one per letter (00_07 HW.1).
#
#   bundle exec ruby scripts/letter_body.rb FILE --out DIR [--heading PREFIX] [--signature "Line 1|Line 2"]
#       [--replace-line "OLD=>NEW"]... [--cover HTML_FILE] [--table-border]
#   bundle exec ruby scripts/letter_body.rb --selftest
#
# What it does, in order: picks the region between the copy markers (the same regexes
# `scripts/copy_region_check.rb` judges — read from that file, never restated here), takes the
# subject line out of the body, applies exact-line replacements (each must match ONE line),
# turns the signature placeholder into the given lines, detaches a line glued to a list item
# (Redcarpet lazy continuation — #13 (а)), renders with and without `lax_spacing` and refuses
# when they differ, and asserts: list items and ordered lists match the source, no Markdown,
# placeholder or subject leaked into the body, no closing formula («З повагою,» / «Kind regards,»)
# glued to its signature lines by soft breaks — a region WITHOUT a signature placeholder renders its
# signature block as one <p> with newlines, which Gmail shows as ONE line (FEA/Prony, 2026-11-07:
# caught by eye before Send; seven more regions in the tree had the same shape). Writes body.html · subject.txt · inject.js and
# prints the SHA-256 of the HTML — the hash the in-page check compares against (#13 (б)).
#
# Declared ceiling — what a green run does NOT prove:
#   · letter-specific structure (lettered sub-items of one question, a table's row count, the
#     place of a named paragraph) — pass those as --replace-line guards or check by eye;
#   · that «item N» / «п. N» in the text points at the item it MEANS — the visible number is asserted
#     (a section continuing the numbering gets `start=`, since 2026-11-07), the meaning is not;
#   · the PDF annex of a letter (DMLS) — its own recipe lives above that region;
#   Which assert catches what, measured by mutation 2026-11-07: an indented continuation that closes
#   a list is caught ONLY by the ordered-list count; lax ≡ strict guards the normalisation of a list
#   glued under a paragraph (switch it off and the clean case reds on that assert, and only there).
#   A lost list start (Redcarpet drops it) is caught by the visible-numbering assert — switch off the
#   `start=` rewrite and the sectioned case reds there (mutation 2026-11-07). The glued closing
#   formula is caught only by its own assert — switch it off and the unsigned case reds there.
#   · anything that happens in Gmail after the HTML is built (Trusted Types, Cc, attachments) —
#     the rest of #13.

require "digest"
require "json"
require "fileutils"
require "nokogiri"
require "redcarpet"

module LetterBody
  ROOT = File.expand_path("..", __dir__)
  GUARD_SRC = File.read(File.join(ROOT, "scripts", "copy_region_check.rb"))
  MARKER = Regexp.new(GUARD_SRC[/^MARKER\s*=\s*\/(.+)\/\s*$/, 1] || abort("MARKER not found in copy_region_check.rb"))
  END_MARK = Regexp.new(GUARD_SRC[/^END_MARK\s*=\s*\/(.+)\/\s*$/, 1] || abort("END_MARK not found in copy_region_check.rb"))
  SUBJECT_LINE = /\A\*\*(?:Тема|Subject line):\*\*\s*(.+?)\s*\z/
  SUBJECT_HEADING = /\A#+\s*(?:Тема|Subject line)\s*\z/
  SIGNATURE_PLACEHOLDER = /\A`\[[^\]]*(?:signature|підпис)[^\]]*\]`\s*\z/i
  CLOSING = /\A(?:З повагою|З найкращими побажаннями|Kind regards|Best regards|With best regards|Sincerely|Regards),/
  LIST_ITEM = /\A(\s*)(?:[-*+]|\d+\.)\s+\S/
  NUMBERED = /\A\d+\.\s+\S/
  MARKER_TOKEN = "SIGNATUREMARKER"

  class Failure < StandardError; end

  module_function

  def fail!(msg) = raise(Failure, msg)

  def region(lines, heading: nil)
    from = 0
    if heading
      from = lines.index { |l| l.start_with?("#") && l.include?(heading) } or fail!("heading not found: #{heading}")
    end
    a = (from...lines.size).find { |i| lines[i].match?(MARKER) } or fail!("no start marker after line #{from + 1}")
    b = ((a + 1)...lines.size).find { |i| lines[i].match?(END_MARK) } or fail!("no end marker after line #{a + 1}")
    lines[(a + 1)...b].map(&:chomp)
  end

  def take_subject(body)
    i = body.index { |l| l.match?(SUBJECT_LINE) }
    return [ body[i][SUBJECT_LINE, 1], body.reject.with_index { |_, k| k == i } ] if i

    h = body.index { |l| l.match?(SUBJECT_HEADING) } or fail!("no subject line («**Тема:**» / «**Subject line:**» or a «Subject line» heading)")
    s = ((h + 1)...body.size).find { |k| !body[k].strip.empty? } or fail!("subject heading without a subject")
    [ body[s].strip, body.reject.with_index { |_, k| k == h || k == s } ]
  end

  def replace_lines(body, pairs)
    pairs.each do |old, new|
      idx = body.each_index.select { |k| body[k] == old }
      fail!("replace-line matched #{idx.size} lines (need 1): #{old[0, 80]}") unless idx.size == 1
      body[idx.first] = new
    end
    body.compact.reject { |l| l == "\0" }
  end

  def place_signature(body, signature)
    idx = body.each_index.select { |k| body[k].match?(SIGNATURE_PLACEHOLDER) }
    fail!("#{idx.size} signature placeholders (need 0 or 1)") if idx.size > 1
    if idx.empty?
      fail!("--signature given, but the region has no signature placeholder") if signature
      return body
    end
    fail!("the region has a signature placeholder — pass --signature") unless signature
    body[idx.first] = MARKER_TOKEN
    body
  end

  # Redcarpet glues a non-blank, non-list, non-indented line that follows a list item onto that item;
  # and a list that starts right under a paragraph line renders only with `lax_spacing`. Both get a
  # blank line, so that the lax ≡ strict assert below is left judging the one real defect: an
  # indented continuation that closes a list (#13 (а)).
  def detach_glued(body)
    out = []
    detached = 0
    body.each_with_index do |l, k|
      prev = k.positive? ? body[k - 1] : nil
      if prev && !prev.strip.empty?
        glued = prev.match?(LIST_ITEM) && !l.strip.empty? && !l.match?(LIST_ITEM) && !l.start_with?(" ", "\t")
        list_start = l.match?(LIST_ITEM) && !l.start_with?(" ", "\t") && !prev.match?(LIST_ITEM)
        if glued || list_start
          out << ""
          detached += 1 if glued
        end
      end
      out << l
    end
    [ out, detached ]
  end

  def source_counts(body)
    items = body.count { |l| l.match?(LIST_ITEM) }
    groups = 0
    in_group = false
    body.each do |l|
      if l.match?(NUMBERED)
        groups += 1 unless in_group
        in_group = true
      elsif !l.strip.empty? && !l.start_with?(" ", "\t") # an indented continuation belongs to its item
        in_group = false
      end
    end
    [ items, groups ]
  end

  # The numbers each source list carries — Redcarpet keeps only the COUNT of a list, never the number
  # it starts at, so a section that continues the numbering («12.» under a heading) renders as «1.»
  # and every «п. 12» of the text points at nothing (2026-11-07, accelerated-corrosion ТЗ).
  def source_groups(body)
    groups = []
    in_group = false
    body.each do |l|
      if (n = l[/\A(\d+)\.\s+\S/, 1])
        in_group ? groups.last << n.to_i : groups << [ n.to_i ]
        in_group = true
      elsif !l.strip.empty? && !l.start_with?(" ", "\t")
        in_group = false
      end
    end
    groups
  end

  # [start, top-level item count] of every <ol> as a reader sees it; items of a nested list don't count.
  def visible_lists(html)
    out = []
    stack = []
    html.scan(%r{<(/?)(ol|ul|li)\b([^>]*)>}) do |close, tag, attrs|
      if tag == "li"
        out[stack.last[1]][1] += 1 if close.empty? && stack.last&.first == "ol"
      elsif close.empty?
        out << [ (attrs[/start="(\d+)"/, 1] || 1).to_i, 0 ] if tag == "ol"
        stack << [ tag, tag == "ol" ? out.size - 1 : nil ]
      else
        stack.pop
      end
    end
    out
  end

  def render(md, lax:)
    Redcarpet::Markdown.new(Redcarpet::Render::HTML.new, tables: true, no_intra_emphasis: true, lax_spacing: lax).render(md)
  end

  def assemble(lines, heading: nil, signature: nil, replacements: [], cover: nil, table_border: false)
    body = region(lines, heading: heading)
    subject, body = take_subject(body)
    body = replace_lines(body, replacements)
    body = place_signature(body, signature)
    body, detached = detach_glued(body)
    items, groups = source_counts(body)
    md = body.join("\n") + "\n"
    html = render(md, lax: true)
    fail!("render depends on lax_spacing — a list stands glued under a paragraph that the normalisation missed (#13 (а))") unless html == render(md, lax: false)
    li = html.scan("<li>").size
    ol = html.scan("<ol").size
    fail!("list items: html #{li} ≠ source #{items}") unless li == items
    fail!("ordered lists: html #{ol} ≠ source #{groups} — an indented continuation closed a list (#13 (а))") unless ol == groups
    numbers = source_groups(body)
    numbers.each { |g| fail!("source list numbering not consecutive: #{g.join(',')}") unless g == (g.first...(g.first + g.size)).to_a }
    k = -1
    html = html.gsub("<ol>") { k += 1; (st = numbers[k]&.first) && st != 1 ? %(<ol start="#{st}">) : "<ol>" }
    want = numbers.map { |g| [ g.first, g.size ] }
    fail!("visible numbering #{visible_lists(html).inspect} ≠ source #{want.inspect} — «п. N» would point at nothing (#13 (а))") unless visible_lists(html) == want
    if signature
      sig = "<p>#{signature.split('|').join('<br>')}</p>"
      fail!("signature marker not rendered as its own paragraph") unless html.include?("<p>#{MARKER_TOKEN}</p>")
      html = html.sub("<p>#{MARKER_TOKEN}</p>", sig)
    end
    # Parsed, not tag-stripped: a regex strip keeps entities, so a subject with «&» leaked into the
    # body (rendered «&amp;») went unseen (selftest «subject with & leaked»; CodeQL #523).
    text = Nokogiri::HTML::DocumentFragment.parse(html).text
    fail!("Markdown leaked: #{text[/\*\*|`|^#+ /]}") if text.match?(/\*\*|`|^#+ /)
    glued = html.scan(%r{<p>((?:(?!</p>).)*)</p>}m).flatten.find { |x| x.match?(CLOSING) && x.include?("\n") }
    fail!("closing formula glued to its signature by soft breaks («#{glued[0, 40].tr("\n", " ")}…») renders as ONE line in Gmail — " \
          "turn the block into a signature placeholder with --replace-line and pass --signature (#13 (а))") if glued
    fail!("placeholder leaked: #{text[/\[[^\]]{1,80}\]/]}") if text.match?(/\[[^\]]{1,80}\]/)
    fail!("subject leaked into the body") if text.include?(subject)
    fail!("marker leaked into the body") if text.include?(MARKER_TOKEN) || text.match?(MARKER) || text.match?(END_MARK)
    html = html.gsub("<table>", '<table style="border-collapse:collapse" border="1" cellpadding="4">') if table_border
    html = "#{cover}\n<hr>\n#{html}" if cover
    { html: html, subject: subject, li: li, ol: ol, p: html.scan("<p>").size, detached: detached,
      sha256: Digest::SHA256.hexdigest(html) }
  end

  def write(res, dir)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "body.html"), res[:html])
    File.write(File.join(dir, "subject.txt"), res[:subject])
    File.write(File.join(dir, "inject.js"),
               "window.__letterBody = #{res[:html].to_json};\nwindow.__letterSubject = #{res[:subject].to_json};\n" \
               "[window.__letterBody.length, window.__letterSubject];\n")
  end

  def selftest
    region = ->(body) { [ "# Doc", "", "## 📤 Dispatch block (UA) — test", "", "**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** x", "", *body, "", "**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** y" ] }
    clean = [ "**Тема:** Тестовий запит", "", "Шановні колеги!", "", "**1. Розміри.** Текст.", "", "Список:", "- (а) один;", "- (б) два.", "",
             "1. **Перше** питання.", "2. **Друге** питання.", "", "`[підпис і контакти відправника — заповнити перед відправкою]`" ]
    cases = 0
    ok = ->(name, cond) { cases += 1; abort "SELFTEST FAIL: #{name}" unless cond }
    bad = lambda do |name, lines, **kw|
      cases += 1
      begin
        assemble(lines, **kw)
        abort "SELFTEST FAIL (must refuse): #{name}"
      rescue Failure
        nil
      end
    end
    r = assemble(region.(clean), signature: "З повагою,|Олексій Лукін")
    ok.("clean: subject", r[:subject] == "Тестовий запит")
    ok.("clean: li", r[:li] == 4)
    ok.("clean: ol", r[:ol] == 1)
    ok.("clean: signature", r[:html].include?("<p>З повагою,<br>Олексій Лукін</p>"))
    ok.("clean: nothing detached", r[:detached].zero?)
    glued = clean.dup.insert(clean.index("- (б) два.") + 1, "Рядок, що мав би стояти окремо.")
    g = assemble(region.(glued), signature: "Олексій Лукін")
    ok.("glued line detached", g[:detached] == 1 && g[:html].include?("<p>Рядок, що мав би стояти окремо.</p>"))
    bad.("placeholder leaked", region.(clean + [ "", "Адресат: [Імʼя Прізвище]" ]), signature: "x")
    bad.("signature placeholder without --signature", region.(clean))
    bad.("indented continuation closes the list", region.(clean.dup.insert(clean.index("1. **Перше** питання.") + 1, "", "  Продовження першого пункту.")), signature: "x")
    bad.("no end marker", region.(clean)[0..-2], signature: "x")
    bad.("replace-line not unique", region.(clean + [ "", "Шановні колеги!" ]), signature: "x", replacements: [ [ "Шановні колеги!", "Добрий день!" ] ])
    bad.("replace-line absent", region.(clean), signature: "x", replacements: [ [ "Немає такого рядка", "x" ] ])
    bad.("no subject", region.(clean.drop(2)), signature: "x")
    rr = assemble(region.(clean), signature: "x", replacements: [ [ "Шановні колеги!", "Добрий день!" ] ])
    ok.("replace-line applied", rr[:html].include?("<p>Добрий день!</p>"))
    sect = clean + [ "", "**Розділ 2.**", "", "3. Третє питання.", "4. Четверте питання." ]
    sr = assemble(region.(sect), signature: "x")
    ok.("section continues numbering", sr[:html].include?('<ol start="3">') && sr[:html].scan("<ol>").size == 1)
    nest = clean + [ "", "**Розділ 2.**", "", "3. Третє:", "   - вкладений;", "   - ще один.", "4. Четверте." ]
    ok.("nested list does not count as items", assemble(region.(nest), signature: "x")[:html].include?('<ol start="3">'))
    bad.("closing formula glued by soft breaks", region.(clean[0..-2] + [ "З повагою,", "Олексій Лукін" ]))
    bad.("numbering gap inside a list", region.(clean.map { |l| l == "2. **Друге** питання." ? "3. **Друге** питання." : l }), signature: "x")
    amp = clean.map { |l| l.start_with?("**Тема:**") ? "**Тема:** Запит R&D «A»" : l }
    ok.("subject with & not leaked", assemble(region.(amp), signature: "x")[:subject] == "Запит R&D «A»")
    bad.("subject with & leaked", region.(amp + [ "", "Запит R&D «A»" ]), signature: "x")
    puts "letter_body selftest: #{cases} cases OK"
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.first == "--selftest"
    LetterBody.selftest
    exit 0
  end
  file = ARGV.shift or abort "usage: letter_body.rb FILE --out DIR [options] | --selftest"
  opts = { replacements: [] }
  out = nil
  until ARGV.empty?
    case (a = ARGV.shift)
    when "--out" then out = ARGV.shift
    when "--heading" then opts[:heading] = ARGV.shift
    when "--signature" then opts[:signature] = ARGV.shift
    when "--replace-line"
      old, new = ARGV.shift.split("=>", 2)
      abort "--replace-line needs OLD=>NEW" unless new
      opts[:replacements] << [ old, new.empty? ? "\0" : new ]
    when "--cover" then opts[:cover] = File.read(ARGV.shift)
    when "--table-border" then opts[:table_border] = true
    else abort "unknown option: #{a}"
    end
  end
  abort "--out DIR is required" unless out
  begin
    res = LetterBody.assemble(File.readlines(file), **opts)
  rescue LetterBody::Failure => e
    abort "REFUSED: #{e.message}"
  end
  LetterBody.write(res, out)
  puts "subject (#{res[:subject].size} chars): #{res[:subject]}"
  puts "html #{res[:html].bytesize} B · p #{res[:p]} · li #{res[:li]} · ol #{res[:ol]} · detached #{res[:detached]}"
  puts "sha256 #{res[:sha256]}"
end
