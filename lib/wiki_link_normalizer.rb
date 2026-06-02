# frozen_string_literal: true

require "pathname"
require "set"

# [OPS] WikiLinkNormalizer — rewrites markdown links in a canonical SSOT doc
# (docs/NN_NN_*.md) so they keep resolving once the doc is published to the
# GitHub *wiki* (a separate git repo whose pages are named after the docs, with
# no `.md` suffix and a flat namespace).
#
# Pure string transform — no Rails, no network, no filesystem writes — so it is
# unit-testable. Filesystem existence is injected via `exists:` so specs can
# stub it.
#
# Link classes actually present in docs/ (verified 2026-05-30) and how each is
# handled:
#   * external (http/https/mailto) or pure `#anchor`     → untouched
#   * link to a canonical doc (basename ∈ canon_slugs),
#     with any `.md` / `./` / `../` / `docs/` noise       → bare wiki link `Slug[#anchor]`
#   * image `![](…)` to a file that exists in the repo    → recorded for carry-over
#                                                           into the wiki, rewritten
#                                                           to `images/<basename>`
#   * link to any other existing repo file                → absolute github.com blob URL
#   * anything unresolved                                 → untouched + recorded warning
#
# Links inside fenced ``` / ~~~ code blocks AND inline `code` spans are left
# untouched (so example code that merely looks like a link — e.g. the cross-ref
# format examples in 00_06 — is not rewritten or reported as unresolved).
class WikiLinkNormalizer
  Result = Struct.new(:body, :images, :unresolved, keyword_init: true)

  # Matches inline links/images: `[text](target)` and `![alt](target)`, with an
  # optional Markdown title (`(target "title")`). Targets contain no spaces.
  LINK_RE = /(!?)\[([^\]]*)\]\(\s*([^)\s]+)(?:\s+"[^"]*")?\s*\)/

  # Inline code span: a run of N backticks … the next run of exactly N backticks
  # (so ``[`05_05`](Doc)`` and `[a](b)` examples are recognised as code, not links).
  INLINE_CODE_RE = /(`+).*?\1/

  # @param canon_slugs [Enumerable<String>] doc filenames without the ".md"
  # @param repo        [String] "owner/name"
  # @param exists      [#call]  ->(repo_relative_path) => Boolean
  # @param branch      [String] default branch the blob/raw URLs point at
  def initialize(canon_slugs:, repo:, exists:, branch: "main")
    @slugs  = canon_slugs.to_set
    @repo   = repo
    @exists = exists
    @branch = branch
  end

  def call(body)
    images     = []
    unresolved = []
    fenced     = false
    out = +""

    body.each_line do |line|
      if line.lstrip.start_with?("```", "~~~")
        fenced = !fenced
        out << line
      elsif fenced
        out << line
      else
        out << rewrite_outside_code_spans(line, images, unresolved)
      end
    end

    Result.new(body: out, images: images.uniq, unresolved: unresolved.uniq)
  end

  private

  # Rewrite links only in the parts of a line OUTSIDE inline code spans; the
  # spans themselves are copied verbatim (GitHub never renders a link inside
  # `code`, so example links must not be rewritten or flagged unresolved).
  def rewrite_outside_code_spans(line, images, unresolved)
    spans = code_span_ranges(line)
    line.gsub(LINK_RE) do
      m = Regexp.last_match
      # Skip a link ONLY when the WHOLE `[..](..)` sits inside one inline code
      # span (a verbatim example). A link whose LABEL merely contains inline
      # code — e.g. [`05_05`](target), the canonical cross-ref form — is a real
      # link (its `](target)` is outside any span) and must still be rewritten.
      if spans.any? { |r| r.cover?(m.begin(0)) && r.cover?(m.end(0) - 1) }
        m[0]
      else
        "#{m[1]}[#{m[2]}](#{rewrite(m[1], m[3], images, unresolved)})"
      end
    end
  end

  # Char ranges of inline code spans (a run of N backticks … the next run of N).
  def code_span_ranges(line)
    ranges = []
    pos = 0
    while (m = INLINE_CODE_RE.match(line, pos))
      ranges << (m.begin(0)...m.end(0))
      pos = m.end(0)
    end
    ranges
  end

  def rewrite(bang, raw, images, unresolved)
    return raw if raw.match?(%r{\A(?:https?:|mailto:|#)})

    path, fragment = raw.split("#", 2)
    anchor = fragment ? "##{fragment}" : ""

    if bang == "!"
      repo_path = resolve(path)
      if repo_path
        images << repo_path
        return "images/#{File.basename(repo_path)}"
      end
      unresolved << raw
      return raw
    end

    slug = File.basename(path).delete_suffix(".md")
    return "#{slug}#{anchor}" if @slugs.include?(slug)

    repo_path = resolve(path)
    return "https://github.com/#{@repo}/blob/#{@branch}/#{repo_path}#{anchor}" if repo_path

    unresolved << raw
    raw
  end

  # Resolve a link target (written relative to docs/, but the corpus mixes in
  # stray `../` prefixes) to an existing repo-relative path. Tries the most
  # correct interpretation first, then progressively looser fallbacks; returns
  # nil if nothing on disk matches (caller leaves the link untouched + warns).
  def resolve(path)
    stripped = path.gsub(%r{\A(?:\.\./)+}, "").delete_prefix("./")
    [
      Pathname("docs").join(path).cleanpath.to_s, # docs-relative (canonical intent)
      stripped,                                    # repo-root-relative (e.g. ../tools/…)
      "docs/#{stripped}"                           # docs/ + de-dotted (inconsistent ../protocols/…)
    ].uniq.find { |c| @exists.call(c) }
  end
end
