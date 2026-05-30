# frozen_string_literal: true

# [SSOT anti-drift] Auto-generated per-doc Table of Contents for docs/*.md
# (00_06). The GitHub *Wiki* has no automatic outline, so each canon doc needs
# an in-file ToC — but a hand-maintained list drifts (the same trap as volatile
# counts), so it is GENERATED from the doc's own `## ` headings between
# `<!-- TOC:AUTO:START -->` / `<!-- TOC:AUTO:END -->` markers and CI-verified in
# sync (`rake docs:toc` writes; `docs:check_refs` fails on drift). Pure functions,
# no Rails — mirrors the lib/tracker/dashboard.rb regen-between-markers pattern.
module DocsToc
  module_function

  START_MARK = "<!-- TOC:AUTO:START -->"
  END_MARK   = "<!-- TOC:AUTO:END -->"
  HEADING    = "## 📑 Зміст"
  # Front-matter headings excluded from the ToC (the ToC maps the *content*).
  FRONT = /Мета|Статус|Cross-references|Зміст/

  # GitHub heading-anchor slug — validated against real repo anchors. Lowercase;
  # drop emoji / punctuation / em-dash (keep letters, digits, `_`, `-`, space);
  # drop variation-selectors / ZWJ / combining marks; spaces → hyphens.
  def github_anchor(text)
    s = text.strip.downcase
    s = s.gsub(/[^\p{Word}\- ]/u, "")
    s = s.gsub(/[\p{Mn}\p{Me}\p{Cf}]/u, "")
    s.gsub(" ", "-")
  end

  # Clean display text for a ToC line: strip leading/trailing emoji + marks, drop
  # code spans and `[TAG]`s (both would break the markdown link), collapse spaces.
  def link_text(heading)
    t = heading.sub(/\A[\p{S}\p{Cf}\p{Mn}\p{Me}\s\u{FE0F}]+/u, "")
    t = t.gsub(/[\p{S}\p{Cf}\p{Mn}\p{Me}\u{FE0F}\s]+\z/u, "")
    t = t.gsub(/`[^`]*`/, "")
    t = t.gsub(/\[[^\]]*\]/, "")
    t = t.gsub(/\(\s*\)/, "")
    t.gsub(/\s+/, " ").strip
  end

  # Content `## ` headings (skips front-matter + lines inside ``` fences).
  def content_headings(markdown)
    in_fence = false
    markdown.each_line.filter_map do |line|
      in_fence = !in_fence if line.start_with?("```")
      next if in_fence
      next unless line.start_with?("## ")

      heading = line.sub(/\A##\s/, "").rstrip
      heading unless heading.match?(FRONT)
    end
  end

  # Existing trailing descriptions (" — …" after a ToC link), keyed by anchor, so a
  # curated description (04_01-style) survives regeneration of titles/anchors.
  def existing_descriptions(markdown)
    block = markdown[/#{Regexp.escape(START_MARK)}(.*?)#{Regexp.escape(END_MARK)}/m, 1]
    return {} unless block

    block.each_line.each_with_object({}) do |line, h|
      m = line.match(/\A- \[[^\]]*\]\(#([^)]*)\)\s*(—\s.*\S)\s*\z/)
      # normalize the parsed anchor (strip variation-selectors/marks) so a curated
      # hand-ToC anchor (e.g. `#️-0-…` with VS) matches the clean github_anchor key.
      h[m[1].gsub(/[\p{Mn}\p{Me}\p{Cf}]/u, "")] = " #{m[2]}" if m
    end
  end

  # The ToC body (`- [..](#..)` lines) from current headings; any curated
  # `— description` present in the existing block is preserved per anchor.
  def render_body(markdown)
    desc = existing_descriptions(markdown)
    content_headings(markdown).map do |h|
      anchor = github_anchor(h)
      "- [#{link_text(h)}](##{anchor})#{desc[anchor] || ''}"
    end.join("\n")
  end

  def markers?(markdown)
    markdown.include?(START_MARK) && markdown.include?(END_MARK)
  end

  # Regenerate the ToC between existing markers. Returns [new_markdown, changed?].
  # No-op (placement is a one-time manual step) when markers are absent.
  def regen(markdown)
    return [ markdown, false ] unless markers?(markdown)

    replacement = "#{START_MARK}\n#{render_body(markdown)}\n#{END_MARK}"
    new_md = markdown.sub(/#{Regexp.escape(START_MARK)}.*?#{Regexp.escape(END_MARK)}/m, replacement)
    [ new_md, new_md != markdown ]
  end
end
