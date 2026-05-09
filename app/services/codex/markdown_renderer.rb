# frozen_string_literal: true

# Codex::MarkdownRenderer — minimal, safe markdown -> HTML renderer for
# Codex lore fields (`context_md`, `cyber_meaning_md`, `lore_md`) and user
# comments (`body_md`, Phase 2).
#
# Why not Redcarpet/Kramdown? — the lore content is hand-curated YAML
# (predominantly plain prose with `**bold**`, `_italic_`, lists,
# blockquotes, links). Pulling a full markdown gem would add an
# unnecessary dependency for a tiny, well-scoped surface.
#
# Strategy:
#   1. Convert a small subset of markdown to safe HTML primitives.
#   2. Pass through Rails Sanitizer with an explicit safelist (mirrors the
#      tag set declared in the SSOT — docs/04_05 §12).
#   3. Always return an html_safe string.
#
# This keeps the attack surface tiny (no `<script>`, no event handlers,
# no `style=`).
module Codex
  module MarkdownRenderer
    module_function

    SAFE_TAGS = %w[p h2 h3 h4 ul ol li strong em blockquote code pre a br].freeze
    SAFE_ATTRS = %w[href].freeze

    def render(markdown)
      return "".html_safe if markdown.blank?

      html = to_html(markdown.to_s)
      Rails::HTML5::SafeListSanitizer.new.sanitize(
        html, tags: SAFE_TAGS, attributes: SAFE_ATTRS
      ).html_safe
    end

    # ------------------------------------------------------------------
    # Internal: tiny markdown-ish converter. Intentionally simple.
    # ------------------------------------------------------------------
    def to_html(text)
      escaped = ERB::Util.html_escape(text)

      # Block-level: split on blank lines into paragraphs
      blocks = escaped.split(/\n{2,}/)
      blocks.map { |b| transform_block(b) }.join("\n")
    end

    def transform_block(block)
      stripped = block.strip
      return "" if stripped.empty?

      if stripped.start_with?("### ")
        "<h4>#{inline(stripped.sub(/^###\s+/, ''))}</h4>"
      elsif stripped.start_with?("## ")
        "<h3>#{inline(stripped.sub(/^##\s+/, ''))}</h3>"
      elsif stripped.start_with?("# ")
        "<h2>#{inline(stripped.sub(/^#\s+/, ''))}</h2>"
      elsif stripped.match?(/\A&gt;\s/)
        body = stripped.lines.map { |l| l.sub(/\A&gt;\s?/, "") }.join(" ")
        "<blockquote>#{inline(body.strip)}</blockquote>"
      elsif stripped.lines.all? { |l| l.match?(/\A\s*[-*]\s+/) }
        items = stripped.lines.map { |l| "<li>#{inline(l.sub(/\A\s*[-*]\s+/, '').strip)}</li>" }.join
        "<ul>#{items}</ul>"
      elsif stripped.lines.all? { |l| l.match?(/\A\s*\d+\.\s+/) }
        items = stripped.lines.map { |l| "<li>#{inline(l.sub(/\A\s*\d+\.\s+/, '').strip)}</li>" }.join
        "<ol>#{items}</ol>"
      else
        "<p>#{inline(stripped.gsub(/\n/, '<br>'))}</p>"
      end
    end

    # Inline conversions: links, bold, italic, inline code.
    def inline(text)
      text
        .gsub(/`([^`]+)`/) { "<code>#{Regexp.last_match(1)}</code>" }
        .gsub(/\*\*([^*]+)\*\*/) { "<strong>#{Regexp.last_match(1)}</strong>" }
        .gsub(/(?<![\w*])\*([^*\n]+)\*(?![\w*])/) { "<em>#{Regexp.last_match(1)}</em>" }
        .gsub(/(?<![\w_])_([^_\n]+)_(?![\w_])/) { "<em>#{Regexp.last_match(1)}</em>" }
        .gsub(/\[([^\]]+)\]\(([^)]+)\)/) do
          label = Regexp.last_match(1)
          href  = Regexp.last_match(2)
          # Allow only http(s) and mailto schemes; sanitizer also strips,
          # but we filter early to avoid even constructing dangerous tags.
          safe_href = href.match?(/\A(https?:|mailto:)/) ? href : "#"
          %(<a href="#{safe_href}" rel="noopener noreferrer" target="_blank">#{label}</a>)
        end
    end
  end
end
