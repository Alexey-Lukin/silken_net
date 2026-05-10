# frozen_string_literal: true

require "rails_helper"

RSpec.describe Codex::Show do
  # Codex::Show wires several Codex sub-components together (Comments::Thread,
  # Attunements::Toggle, MarkdownRenderer, MetaRow, StatusBadge). The
  # `render_component` helper detects route-helper usage in those children
  # and routes through `ApplicationController.renderer` to provide the full
  # request context.

  let(:realm) do
    create(:codex_realm, slug: "ecosystem", name_en: "Ecosystems", name_uk: "Екосистеми")
  end

  let(:node) do
    create(
      :codex_node,
      :with_lore,
      realm: realm,
      slug: "cherkasy-bir",
      codex_uid: "CDX-ECO-0001",
      title_uk: "Черкаський бір",
      title_en: "Cherkasy Pine Forest",
      subtitle_en: "Pine cathedral of the Dnipro",
      lifecycle_status: :thriving,
      attunement_count: 11,
      attunement_elo: 1700,
      discovery_count: 4,
      citation_count: 2,
      geo_region: "cherkasy-bir",
      external_refs: [
        { "label" => "Wikipedia", "url" => "https://wiki.example.com/cherkasy" },
        { "label" => nil,         "url" => "https://only-url.example.com" }
      ]
    )
  end

  let(:html) do
    render_component(
      node: node,
      current_user: nil,
      comments: [],
      current_user_attuned: false
    )
  end

  describe "hero" do
    it "renders the codex_uid eyebrow, bilingual title and subtitle" do
      expect(html).to include("CDX-ECO-0001")
      expect(html).to include("Черкаський бір")
      expect(html).to include("Cherkasy Pine Forest")
      expect(html).to include("Pine cathedral of the Dnipro")
    end

    it "renders the realm name_en in the hero watermark and in the meta Realm row" do
      # The realm name appears in at least two distinct contexts:
      # 1. The decorative watermark inside the hero section
      # 2. The "Realm" label row in the metadata panel
      expect(html).to include("Ecosystems")
      expect(html.scan("Ecosystems").length).to be >= 2
    end

    it "omits the subtitle when blank" do
      node.update!(subtitle_en: nil)
      expect(html).not_to include("Pine cathedral of the Dnipro")
    end
  end

  describe "lore columns" do
    it "renders all three lore sections when the markdown bodies are present" do
      expect(html).to include(">Context<")
      expect(html).to include(">Cyber Meaning<")
      expect(html).to include(">Lore<")
    end

    it "transforms markdown to safe HTML via Codex::MarkdownRenderer" do
      # Factory `:with_lore` uses `**Context** with [link](https://example.com).`
      expect(html).to include("<strong>Context</strong>")
      expect(html).to include('href="https://example.com"')
      expect(html).to include('rel="noopener noreferrer"')
    end

    it "omits each lore section whose markdown is blank" do
      node.update!(context_md: nil, cyber_meaning_md: nil, lore_md: nil)
      # Headings should disappear with the body
      expect(html).not_to include(">Context<")
      expect(html).not_to include(">Cyber Meaning<")
      expect(html).not_to include(">Lore<")
    end
  end

  describe "aside / metadata panel" do
    it "renders Realm, Archetype, Geo Region and the four counters" do
      aggregate_failures do
        expect(html).to include("Realm")
        expect(html).to include("Archetype")
        expect(html).to include("Geo Region")
        expect(html).to include("cherkasy-bir")
        expect(html).to include("Discovered")
        expect(html).to include(">4<")          # discovery_count
        expect(html).to include("Cited By")
        expect(html).to include(">2<")          # citation_count
        expect(html).to include("Attunement")
        expect(html).to include("Elo")
        expect(html).to include(">1700<")       # attunement_elo
      end
    end

    it "shows an em-dash when geo_region is blank" do
      node.update!(geo_region: nil)
      # Look for the geo row specifically (em-dash also used for missing realm name)
      expect(html).to include("Geo Region")
      expect(html).to include("—")
    end
  end

  describe "external references" do
    it "renders one <li> per external_refs entry with target=_blank + rel=noopener" do
      expect(html).to include("External References")
      expect(html).to include('href="https://wiki.example.com/cherkasy"')
      expect(html).to include('href="https://only-url.example.com"')
      expect(html).to include('target="_blank"')
      expect(html).to include('rel="noopener noreferrer"')
    end

    it "uses the URL as link text when the label is blank" do
      expect(html).to include("Wikipedia")
      expect(html).to include("https://only-url.example.com")
    end

    it "omits the External References block entirely when external_refs is empty" do
      node.update!(external_refs: [])
      expect(html).not_to include("External References")
    end
  end

  describe "Attunement toggle wiring" do
    it "passes the current attunement count and the user-attuned flag to the toggle" do
      attuned_html = render_component(
        node: node, current_user: nil, comments: [], current_user_attuned: true
      )
      # Toggle exposes the count via DOM id "codex_node_<id>_attunement_count"
      expect(attuned_html).to include("codex_node_#{node.id}_attunement_count")
      expect(attuned_html).to include(">11<") # node.attunement_count
      expect(attuned_html).to include(">Attuned<")
    end

    it "shows the 'Attune' label when current_user_attuned is false" do
      expect(html).to include(">Attune<")
    end
  end

  describe "design system compliance" do
    it "uses gaia-* tokens, not raw Tailwind colours, in the top-level wrapper" do
      expect(html).to include("border-gaia-border")
      expect(html).to include("bg-gaia-surface")
      # Scoped: the body class list should never contain raw bg-white
      expect(html).not_to include('class="bg-white"')
    end
  end
end
