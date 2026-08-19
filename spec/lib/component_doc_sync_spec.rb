# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../scripts/component_doc_sync"

# [UI.12] Unit coverage for the component-registry gate. Pure functions over a
# throwaway fixture tree (no Rails/DB) — same style as the other standalone
# script-guards.
#
# The battery is organised by ROW FORM rather than by section, because the
# founding defect of this gate was a parser that knew one form out of three and
# reported a drift seven times larger than the real one. Each form therefore
# gets a positive case (drift is caught) AND appears in the green fixture (an
# honest registry is not turned red) — a parser blind to a form is silent, and
# silence here reads exactly like health.
RSpec.describe ComponentDocSync do
  let(:section_61) { "| **StatusBadge** | `status_badge.rb` | `status:` | AASM стан → колір |" }

  let(:section_64_detailed) do
    <<~ROWS.chomp
      | `Wallets::Show` | `wallets/show.rb` | `wallet:` | Деталізація гаманця |
      | `Wallets::BalanceFrameStub` | `wallets/balance_frame_stub.rb` | `wallet_id:` | Locale-вільний payload |
    ROWS
  end

  let(:section_64_compressed) { "| `Alerts` | `Index`, `Row` | `alert:` |" }

  let(:tree) do
    <<~TREE.chomp
          ├── wallets/                # Гаманці
          └── alerts/                 # Тривоги
    TREE
  end

  let(:files) do
    %w[
      app/views/components/application_component.rb
      app/views/components/wallets/show.rb
      app/views/components/wallets/balance_frame_stub.rb
      app/views/components/alerts/index.rb
      app/views/components/alerts/row.rb
      app/views/shared/ui/status_badge.rb
      app/views/shared/iot/metric_value.rb
      app/views/shared/web3/address.rb
    ]
  end

  # A minimal 04_04 carrying every heading the gate anchors on. Each block comes
  # from a `let`, so a case mutates exactly one row form and leaves the rest sane.
  def build_doc
    <<~MD
      ### Ієрархія Компонентів

      ```
      ApplicationComponent (Phlex::HTML)
      │
      └── app/views/components/       # Доменні компоненти
      #{tree}
      ```

      ### Потік Рендерингу

      ### 6.1 Спільні UI Примітиви (`app/views/shared/ui/`)

      | Компонент | Файл | Props | Призначення |
      |---|---|---|---|
      #{section_61}

      #### StatusBadge — Маппінг Станів

      | AASM Стани | Семантичний Стиль |
      |---|---|
      | `pending`, `dormant` | `bg-status-warning` |

      #### Skeleton — Варіанти

      | Варіант | Рядки | Призначення |
      |---|---|---|
      | `:balance` | 3 | Фрейм балансу |

      ### 6.2 Спільні IoT Компоненти (`app/views/shared/iot/`)

      | Компонент | Файл | Props | Призначення |
      |---|---|---|---|
      | **MetricValue** | `metric_value.rb` | `value:` | Значення сенсора |

      ### 6.3 Спільні Web3 Компоненти (`app/views/shared/web3/`)

      | Компонент | Файл | Props | Призначення |
      |---|---|---|---|
      | **Address** | `address.rb` | `address:` | Ethereum-адреса |

      ### 6.4 Доменні Компоненти (`app/views/components/`)

      #### Гаманці

      | Компонент | Файл | Props | Опис |
      |---|---|---|---|
      #{section_64_detailed}

      #### Інші Доменні Компоненти

      | Простір імен | Компоненти | Ключові Props |
      |---|---|---|
      #{section_64_compressed}

      ### 6.5 Namespacing Convention

      ## 10. Lookbook (Дослідник Компонентів)

      | Превью | Сценарії |
      |---|---|
      | `WidgetPreview` | Default |

      ## 11. Що завгодно далі
    MD
  end

  # Builds a throwaway repo root and yields its path.
  def with_root(doc_body: build_doc)
    Dir.mktmpdir do |root|
      doc_path = File.join(root, described_class::DOC_REL)
      FileUtils.mkdir_p(File.dirname(doc_path))
      File.write(doc_path, doc_body)

      files.each do |rel|
        path = File.join(root, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "# fixture\n")
      end
      # Every shared subdir must exist even when a case removes its only file,
      # otherwise the glob is empty for a reason the case did not intend.
      %w[ui iot web3].each { |d| FileUtils.mkdir_p(File.join(root, described_class::SHARED_REL, d)) }

      # 🔴 [2026-08-19] Каталог превʼю + один файл. Доти його НЕ БУЛО, тож четверта
      # вісь у кожному прикладі порівнювала ∅ ⟷ ∅ і не могла нічого сказати — рівно
      # та пастка, від якої застерігає коментар про shared-globи двома рядками вище,
      # застосована до сусідньої осі. Знайдено adversarial-проходом; закривається
      # разом із якорем на §10, який без цієї структури просто кидав.
      previews = File.join(root, described_class::PREVIEWS_REL)
      FileUtils.mkdir_p(previews)
      File.write(File.join(previews, "widget_preview.rb"), "class WidgetPreview; end\n")

      yield root
    end
  end

  # ── the green baseline, and the proof it is not green by emptiness ─────────

  describe "an in-sync registry" do
    it "reports no drift" do
      with_root { |root| expect(described_class.audit(root)).to be_empty }
    end

    # A gate over an empty set is green forever. This pins that the green case
    # above actually compared something — in every arm, not just the first.
    it "has actually inspected a non-empty population in each arm" do
      with_root do |root|
        doc = File.readlines(File.join(root, described_class::DOC_REL), chomp: true)

        domain = described_class.code_classes(
          File.join(root, described_class::COMPONENTS_REL), nested: true,
          reject: described_class::NON_COMPONENT_BASENAMES
        )
        shared = described_class.code_classes(
          File.join(root, described_class::SHARED_REL, "ui"), nested: false
        )

        expect(domain.size).to be >= 4
        expect(shared.size).to be >= 1
        expect(described_class.tree_namespaces(doc).size).to be >= 2
      end
    end

    it "exempts the ApplicationComponent base class from §6.4" do
      with_root do |root|
        expect(described_class.audit(root).join).not_to include("ApplicationComponent")
      end
    end
  end

  # ── row form A: | `Ns::Class` | file | props | desc | ─────────────────────

  describe "row form A (detailed `Ns::Class`)" do
    context "when a component's detailed row is missing" do
      let(:section_64_detailed) { "| `Wallets::Show` | `wallets/show.rb` | `wallet:` | Деталізація |" }

      it "reports it" do
        with_root do |root|
          expect(described_class.audit(root))
            .to contain_exactly(a_string_including("`Wallets::BalanceFrameStub` exists in app/views/components/"))
        end
      end
    end

    context "when a row outlived its file" do
      let(:section_64_detailed) do
        "| `Wallets::Show` | `wallets/show.rb` | `wallet:` | Деталізація |\n" \
          "| `Wallets::BalanceFrameStub` | `wallets/balance_frame_stub.rb` | `wallet_id:` | Payload |\n" \
          "| `Wallets::Ghost` | `wallets/ghost.rb` | — | знято торік |"
      end

      it "reports it" do
        with_root do |root|
          expect(described_class.audit(root))
            .to contain_exactly(a_string_including("`Wallets::Ghost` is in 04_04 §6.4 but has NO file"))
        end
      end
    end
  end

  # ── row form B: | `Ns` | `A`, `B`, `C` | props | ──────────────────────────

  describe "row form B (compressed, one row per namespace)" do
    context "when a leaf is dropped from a compressed row" do
      let(:section_64_compressed) { "| `Alerts` | `Index` | `alert:` |" }

      it "reports it" do
        with_root do |root|
          expect(described_class.audit(root))
            .to contain_exactly(a_string_including("`Alerts::Row` exists in app/views/components/"))
        end
      end
    end

    context "when a compressed row lists a leaf that has no file" do
      let(:section_64_compressed) { "| `Alerts` | `Index`, `Row`, `Badge` | `alert:` |" }

      it "reports it" do
        with_root do |root|
          expect(described_class.audit(root))
            .to contain_exactly(a_string_including("`Alerts::Badge` is in 04_04 §6.4 but has NO file"))
        end
      end
    end
  end

  # ── row form C: | **Name** | file | props | desc | (§6.1–6.3) ─────────────

  describe "row form C (shared primitives, bold)" do
    context "when a shared primitive is missing from §6.1" do
      let(:section_61) { "| **StatCard** | `stat_card.rb` | `label:` | Картка |" }

      it "reports both directions" do
        with_root do |root|
          expect(described_class.audit(root)).to contain_exactly(
            a_string_including("`StatusBadge` exists in app/views/shared/ui/"),
            a_string_including("`StatCard` is in 04_04 §6.1 but has NO file")
          )
        end
      end
    end

    context "when the missing primitive lives in web3, not ui" do
      let(:files) { super() - %w[app/views/shared/web3/address.rb] }

      it "is still reported — iot and web3 are checked too" do
        with_root do |root|
          expect(described_class.audit(root))
            .to contain_exactly(a_string_including("shared/web3: `Address` is in 04_04 §6.3 but has NO file"))
        end
      end
    end

    # The neighbouring-domain-of-one-token trap: §6.1's own range also carries
    # the StatusBadge state map and the Skeleton variant table, whose first cells
    # are code spans as well. A laxer anchor reads `:balance` and `pending` as
    # components and invents phantoms that no edit can ever satisfy.
    it "does not read the state-map or variant tables in §6.1 as components" do
      with_root do |root|
        expect(described_class.audit(root).join).not_to include("balance", "pending", "dormant")
      end
    end
  end

  # ── the §1 hierarchy tree (namespace granularity) ─────────────────────────

  # ── четверта вісь: превʼю Lookbook ⟷ §10 ──────────────────────────────────
  describe "row form D (Lookbook previews, §10)" do
    it "reports a preview whose row outlived its file" do
      with_root do |root|
        FileUtils.rm(File.join(root, described_class::PREVIEWS_REL, "widget_preview.rb"))
        expect(described_class.audit(root))
          .to include(a_string_including("`WidgetPreview` is in 04_04 §10 but has NO file"))
      end
    end

    it "reports a preview file absent from the table" do
      with_root do |root|
        File.write(File.join(root, described_class::PREVIEWS_REL, "gadget_preview.rb"), "x\n")
        expect(described_class.audit(root))
          .to include(a_string_including("`GadgetPreview` exists in").and(a_string_including("NOT in 04_04 §10")))
      end
    end

    # 🔴 ЯКІР: рядок ПОЗА §10 не є реєстром. Без цього приклада вісь читала весь
    # документ, тож приклад-рядок у туторіальній прозі червонив із хибною адресою,
    # а винесений із §10 рядок лишав гейт зеленим при порожній секції.
    it "does not read a preview row that sits outside §10" do
      doc = build_doc.sub("| `WidgetPreview` | Default |", "") +
            "\n## Кудись Інде\n\n| Превью | Сценарії |\n|---|---|\n| `WidgetPreview` | Default |\n"
      with_root(doc_body: doc) do |root|
        expect(described_class.audit(root))
          .to include(a_string_including("`WidgetPreview` exists in").and(a_string_including("NOT in 04_04 §10")))
      end
    end
  end

  describe "the §1 ASCII tree" do
    context "when a namespace directory is absent from the tree" do
      let(:tree) { "    └── wallets/                # Гаманці" }

      it "reports it" do
        with_root do |root|
          expect(described_class.audit(root))
            .to contain_exactly(a_string_including("§1 tree namespace: `alerts` exists in app/views/components/"))
        end
      end
    end

    context "when a tree line's directory is gone" do
      let(:tree) do
        "    ├── wallets/                # Гаманці\n" \
          "    ├── alerts/                 # Тривоги\n" \
          "    └── provisioning/           # Реєстрація"
      end

      it "reports it" do
        with_root do |root|
          expect(described_class.audit(root))
            .to contain_exactly(a_string_including("`provisioning` is in the 04_04 §1 hierarchy tree but has NO file"))
        end
      end
    end
  end

  # ── structural failure must be loud, never a silent empty scan ────────────

  describe "when the doc is restructured out from under it" do
    it "raises rather than scanning an empty range" do
      doc = build_doc.sub("### 6.4 Доменні Компоненти (`app/views/components/`)", "### 6.4а Доменні Компоненти")

      with_root(doc_body: doc) do |root|
        expect { described_class.audit(root) }.to raise_error(ArgumentError, /no line starting with/)
      end
    end

    it "raises when the components node leaves the §1 tree" do
      doc = build_doc.sub("└── app/views/components/       # Доменні компоненти", "└── (порожньо)")

      with_root(doc_body: doc) do |root|
        expect { described_class.audit(root) }.to raise_error(ArgumentError, %r{no app/views/components/ node})
      end
    end
  end
end
