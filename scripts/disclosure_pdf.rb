#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# Disclosure PDF — print a repo Markdown file AT A COMMIT into a submission PDF, and check any
# PDF's text layer against that same source [UNI.3].
#
#   bundle exec ruby scripts/disclosure_pdf.rb render <sha> <md-path> <out.pdf> [title]   # + Google Chrome
#   bundle exec ruby scripts/disclosure_pdf.rb check  <sha> <md-path> <pdf> [--ignore REGEX]...
#   bundle exec ruby scripts/disclosure_pdf.rb --selftest
#
# Relative links become GitHub URLs pinned to <sha>, so incorporation by reference points at
# the dated snapshot, never at a moving `main`. Written for the TDCommons submission of
# `docs/protocols/anchor/defensive_disclosure.md` (2026-10-04, printed from `5bd8636f5`); the
# arXiv leg of UNI.3 can print its paper the same way.
#
# 🔑 Indexers and patent examiners read the TEXT LAYER, not the page, and which extractor a
# given index runs is unknown — so `check` asks two independent ones (poppler `pdftotext`;
# Apple PDFKit when `swift` exists) whether every text block of the source is in the PDF
# verbatim, whitespace-blind. Each rule below is a failure of the first upload candidate,
# measured that way on 2026-10-04: the words were right, the text layer was not.
#   · a colour emoji (⚠️) is drawn as an image and lands out of reading order → the TEXT glyph;
#   · ligatures off — PDFKit read «stiﬀness»;
#   · code in Monaco, at normal weight: of five faces tried, the only one whose underscores
#     PDFKit kept in place («delta_t» read 0 of 16 in Menlo), and Monaco's synthetic bold split
#     «delta_t» again; a bare identifier with an underscore («V_OC») is set as code;
#   · a hyphenated compound never ends a line — poppler drops a line-final hyphen
#     («flavin-|dependent» → «flavindependent»);
#   · a table's first column never wraps (poppler read a wrapped cell across the row), and a
#     heading never ends a page.
#
# ⛔ Ceilings, named: the check compares extracted TEXT, so a glyph drawn wrong but extracted
# right passes, and two extractors agreeing is evidence, not proof, about a third. A PDF that a
# repository re-typeset (cover page, running heads) breaks every block that crosses a page —
# strip its stamps with `--ignore`, then read what stays unmatched by eye.

require "cgi"
require "fileutils"
require "nokogiri"
require "open3"
require "redcarpet"
require "tmpdir"

module DisclosurePdf
  REPO = "https://github.com/Alexey-Lukin/silken_net/blob"
  CHROME = ENV.fetch("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
  LIGATURE_OR_BROKEN = /[\uFB00-\uFB06\uFFFD]/
  CSS = <<~CSS
    @page { size: A4; margin: 18mm 16mm 18mm 16mm; }
    body { font-family: "Helvetica Neue", Arial, sans-serif; font-size: 10pt; line-height: 1.42; color: #111; font-variant-ligatures: none; }
    h1 { font-size: 17pt; margin: 0 0 8pt; } h2 { font-size: 13pt; margin: 14pt 0 6pt; border-bottom: 1px solid #bbb; }
    h3 { font-size: 11pt; margin: 12pt 0 4pt; } blockquote { margin: 6pt 0; padding: 4pt 8pt; border-left: 3px solid #999; background: #f6f6f6; }
    table { border-collapse: collapse; width: 100%; font-size: 9pt; } td, th { border: 1px solid #ccc; padding: 3pt 5pt; vertical-align: top; }
    code { font-family: Monaco, monospace; font-size: 8.4pt; font-weight: normal; } a { color: #0645ad; text-decoration: none; overflow-wrap: anywhere; }
    .warn { font-family: "Apple Symbols"; color: #a15c00; }
    .nw { white-space: nowrap; }
    td:first-child { white-space: nowrap; }
    h1, h2, h3 { break-after: avoid; } tr { break-inside: avoid; }
    .src { font-size: 8.5pt; color: #444; margin-bottom: 10pt; }
  CSS
  SWIFT = <<~SWIFT
    import PDFKit
    let d = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
    print((0..<d.pageCount).map { d.page(at: $0)?.string ?? "" }.joined(separator: "\\n"))
  SWIFT

  module_function

  def html(sha, path, title = nil)
    full, st = Open3.capture2("git", "rev-parse", "--verify", "--quiet", "#{sha}^{commit}")
    abort "not a commit: #{sha}" unless st.success?
    sha = full.strip # links pin the FULL hash — the submitted PDF did, and a short one can grow ambiguous
    src, st = Open3.capture2("git", "show", "#{sha}:#{path}")
    abort "git show #{sha}:#{path} failed" unless st.success?
    base = "#{REPO}/#{sha}/"
    md = src.gsub(/\]\(([^)\s]+)\)/) do
      href = Regexp.last_match(1)
      next "](#{href})" if href.match?(%r{\A(?:https?:|#|mailto:)})

      target = File.expand_path(href.sub(/#.*/, ""), "/#{File.dirname(path)}/").delete_prefix("/")
      "](#{base}#{target}#{href[/#.*/]})"
    end
    md = md.gsub("`/NOTICE`", "[`/NOTICE`](#{base}NOTICE)")
    body = Redcarpet::Markdown.new(Redcarpet::Render::HTML.new, tables: true, fenced_code_blocks: true, autolink: true,
                                                                strikethrough: true, no_intra_emphasis: true).render(md)
    url = "#{base}#{path}"
    hygiene(<<~HTML)
      <!doctype html><html lang="en"><head><meta charset="utf-8"><title>#{CGI.escapeHTML(title || src[/^# (.+)$/, 1].to_s)}</title><style>#{CSS}</style></head>
      <body><p class="src">Source: <a href="#{url}"><code>#{url}</code></a> (git commit #{sha}). All references below are pinned to that commit.</p>
      #{body}</body></html>
    HTML
  end

  # The text-layer rules of the header that live in the markup rather than in the CSS.
  def hygiene(html)
    doc = Nokogiri::HTML(html.gsub(/\u26A0\uFE0F?/, %(<span class="warn">\u26A0\uFE0E</span>)))
    doc.xpath("//body//text()[not(ancestor::pre or ancestor::style)]").each do |t|
      s = CGI.escapeHTML(t.content)
      s = s.gsub(/[[:alnum:]µ.]+(?:-[[:alnum:]µ.]+)+/) { %(<span class="nw">#{Regexp.last_match(0)}</span>) }
      s = s.gsub(/\b[[:alnum:]]+_[[:alnum:]_]+\b/) { %(<code>#{Regexp.last_match(0)}</code>) } if t.ancestors("a").empty? && t.ancestors("code").empty?
      t.replace(Nokogiri::HTML::DocumentFragment.parse(s)) unless s == CGI.escapeHTML(t.content)
    end
    doc.to_html
  end

  def render(sha, path, out, title = nil)
    abort "usage: render <sha> <md-path> <out.pdf> [title]" unless sha && path && out
    out = File.expand_path(out)
    Dir.mktmpdir do |tmp|
      page = File.join(tmp, "page.html")
      File.write(page, html(sha, path, title))
      FileUtils.rm_f(out)
      pid = Process.spawn(CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", "--user-data-dir=#{tmp}/profile",
                          "--print-to-pdf=#{out}", "file://#{page}", %i[out err] => File::NULL, pgroup: true)
      wait_for(pid, out)
    end
    abort "render: Chrome produced no PDF" unless File.size?(out)
    puts "render: #{out} (#{File.size(out)} B)"
  end

  # Headless Chrome may linger after printing (seen 2026-10-04): stop at a stable file, not at exit.
  def wait_for(pid, out)
    deadline = Time.now + 90
    last = -1
    loop do
      size = File.size?(out).to_i
      break if Process.wait(pid, Process::WNOHANG) || (size.positive? && size == last) || Time.now > deadline

      last = size
      sleep 1
    end
    Process.kill("TERM", -pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  def texts(pdf)
    txt, st = Open3.capture2("pdftotext", "-enc", "UTF-8", pdf, "-")
    abort "check: pdftotext failed (poppler)" unless st.success?
    out = { "poppler" => txt }
    return out unless system("command -v swift > /dev/null 2>&1")

    Dir.mktmpdir do |tmp|
      File.write(File.join(tmp, "x.swift"), SWIFT)
      txt, st = Open3.capture2("swift", File.join(tmp, "x.swift"), pdf)
      out["pdfkit"] = txt if st.success?
    end
    out
  end

  def squash(text) = text.gsub(/\s+/, "").delete("\uFE0E\uFE0F")

  def blocks(html)
    Nokogiri::HTML(html).css("h1,h2,h3,p,li,td,th")
            .map { |n| squash(n.xpath("./text()|./*[not(self::ul or self::ol)]").map(&:text).join) }.reject(&:empty?).uniq
  end

  # How far a block matches — the character after it names the class of the divergence.
  def divergence(block, text)
    lo = 0
    hi = block.size
    while lo < hi
      mid = (lo + hi + 1) / 2
      text.include?(block[0, mid]) ? lo = mid : hi = mid - 1
    end
    lo
  end

  def check(sha, path, pdf, ignores = [])
    abort "usage: check <sha> <md-path> <pdf> [--ignore REGEX]..." unless sha && path && pdf
    want = blocks(html(sha, path))
    red = false
    texts(pdf).each do |name, raw|
      raw = raw.lines.grep_v(Regexp.union(ignores)).join unless ignores.empty?
      have = squash(raw)
      miss = want.reject { |b| have.include?(b) }
      puts "#{name}: #{want.size} blocks · unmatched #{miss.size} · ligature/broken chars #{raw.scan(LIGATURE_OR_BROKEN).size}"
      miss.first(5).each do |b|
        i = divergence(b, have)
        puts "  …#{b[[ i - 30, 0 ].max, 60]}  ← diverges at #{b[i].inspect}"
      end
      red ||= miss.any? || raw.match?(LIGATURE_OR_BROKEN)
    end
    exit(red ? 1 : 0)
  end

  def selftest
    fails = 0
    t = lambda do |name, ok|
      puts "#{ok ? 'ok  ' : 'FAIL'} #{name}"
      fails += 1 unless ok
    end
    have = squash("the time delta_t\nis itself \u26A0\uFE0E x; flavin\ndependent")
    t.call("match is whitespace- and selector-blind", have.include?(squash("time delta_t is itself \u26A0\uFE0F x")))
    b = squash("flavin-dependent")
    t.call("a dropped line-final hyphen stays unmatched, diverging at the hyphen", !have.include?(b) && b[divergence(b, have)] == "-")
    h = hygiene(%(<p>V_OC of flavin-dependent \u26A0\uFE0F <code>delta_t</code></p>))
    t.call("a bare identifier is set as code", h.include?("<code>V_OC</code>"))
    t.call("a hyphenated compound is kept on one line", h.include?(%(<span class="nw">flavin-dependent</span>)))
    t.call("a colour emoji becomes the text glyph", h.include?(%(<span class="warn">\u26A0\uFE0E</span>)) && !h.include?("\uFE0F"))
    t.call("code is left alone", h.include?("<code>delta_t</code>") && !h.include?("<code><code>"))
    puts(fails.zero? ? "disclosure_pdf --selftest: OK (6 cases)" : "disclosure_pdf --selftest: #{fails} FAILED")
    exit(fails.zero? ? 0 : 1)
  end
end

if $PROGRAM_NAME == __FILE__
  case ARGV.shift
  when "--selftest" then DisclosurePdf.selftest
  when "render" then DisclosurePdf.render(*ARGV.first(4))
  when "check"
    ignores = []
    while (i = ARGV.index("--ignore"))
      ARGV.delete_at(i)
      ignores << Regexp.new(ARGV.delete_at(i))
    end
    DisclosurePdf.check(*ARGV.first(3), ignores)
  else abort "usage: ruby #{$PROGRAM_NAME} render <sha> <md-path> <out.pdf> [title] | check <sha> <md-path> <pdf> [--ignore REGEX]... | --selftest"
  end
end
