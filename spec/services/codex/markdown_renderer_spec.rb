# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::MarkdownRenderer do
  describe ".render" do
    it "returns html_safe empty string for nil/blank input" do
      expect(described_class.render(nil)).to eq("")
      expect(described_class.render("")).to eq("")
      expect(described_class.render(nil)).to be_html_safe
    end

    it "wraps prose paragraphs in <p>" do
      out = described_class.render("Hello world.")
      expect(out).to include("<p>Hello world.</p>")
    end

    it "drops empty blocks produced by leading/consecutive blank lines" do
      out = described_class.render("\n\nHello world.")
      expect(out).to include("<p>Hello world.</p>")
    end

    it "renders headings of three levels" do
      out = described_class.render("# H1\n\n## H2\n\n### H3")
      expect(out).to include("<h2>H1</h2>")
      expect(out).to include("<h3>H2</h3>")
      expect(out).to include("<h4>H3</h4>")
    end

    it "renders bold and italic markers" do
      out = described_class.render("**Bold** and _italic_ text.")
      expect(out).to include("<strong>Bold</strong>")
      expect(out).to include("<em>italic</em>")
    end

    it "renders inline code" do
      out = described_class.render("Use `delta_t` for charge time.")
      expect(out).to include("<code>delta_t</code>")
    end

    it "renders unordered and ordered lists" do
      ul = described_class.render("- one\n- two\n- three")
      expect(ul).to include("<ul>")
      expect(ul.scan("<li>").size).to eq(3)

      ol = described_class.render("1. first\n2. second")
      expect(ol).to include("<ol>")
    end

    it "renders blockquotes" do
      out = described_class.render("> quoted line")
      expect(out).to include("<blockquote>quoted line</blockquote>")
    end

    it "renders safe http(s) links with rel/target attributes" do
      out = described_class.render("[Wiki](https://example.com)")
      expect(out).to include('href="https://example.com"')
      expect(out).to include('rel="noopener noreferrer"')
      expect(out).to include('target="_blank"')
    end

    it "rewrites javascript: URLs to # before sanitisation" do
      out = described_class.render("[evil](javascript:alert(1))")
      expect(out).not_to include("javascript:")
      expect(out).to include('href="#"')
    end

    it "strips disallowed HTML (e.g. <script>) and escapes its content" do
      out = described_class.render("Hello <script>alert('xss')</script> world")
      expect(out).not_to include("<script>")
      # text content is escaped, not executable
      expect(out).to include("Hello")
      expect(out).to include("world")
    end

    it "escapes raw HTML before transforming markdown" do
      out = described_class.render("<b>not bold</b> but **bold**")
      expect(out).not_to include("<b>not bold</b>")
      expect(out).to include("<strong>bold</strong>")
    end
  end
end
