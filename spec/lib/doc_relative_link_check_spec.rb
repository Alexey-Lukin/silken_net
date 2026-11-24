# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "set"
require_relative "../../scripts/doc_relative_link_check"

# [DOC-T.131] Двигун гейта відносних лінків `docs/**`. Чисті функції, без Rails і без git: дерево
# подається Set-ами, як його збирає `tree_from_git`. Кожен виняток і кожна межа з сусідами має
# власний приклад; які мутації двигуна валять які приклади — тіло коміту, що завів гейт.
RSpec.describe DocRelativeLinkCheck do
  let(:tracker) { "docs/00_07_Action_Plan_Tracker.md" }
  let(:tree) do
    {
      files: Set["docs/protocols/legal/a.md", "tools/x/run.py", "NOTICE", "docs/SECURITY_ASSURANCE_CASE.md",
                 "docs/a+b.md", tracker],
      dirs: Set["docs", "docs/protocols", "docs/protocols/legal", "tools", "tools/x"],
      submodules: [ "firmware/extern/lib" ]
    }
  end

  def v(path, text, filter: nil) = described_class.violations(path, text, tree, filter: filter)
  def hrefs(text) = described_class.relative_hrefs(text).map { |ln, href, _| [ ln, href ] }

  describe ".relative_hrefs" do
    it "бере вбудовані лінки, зображення й `/шлях`; пропускає схему, `//` і чистий якір" do
      text = "[a](x.md) ![i](img.png) [r](/abs) [w](https://e.org) [c](//cdn.x/y) [s](#sec) [m](mailto:a@b)\n"
      expect(hrefs(text)).to eq([ [ 1, "x.md" ], [ 1, "img.png" ], [ 1, "/abs" ] ])
    end

    it "не бачить лінка всередині fence (і з відступом) і code-span — у тому числі з подвійним бектиком" do
      text = "```\n[a](dead.md)\n```\n  ```ruby\n  [b](dead.md)\n  ```\n`[c](dead.md)` ``[`00_07`](Doc)`` `[`00_07` ID](…)`\n"
      expect(hrefs(text)).to be_empty
    end

    it "fence закриває лише той самий символ: ``` усередині ~~~ не розсинхронює файл" do
      expect(hrefs("~~~\n```\n[a](dead.md)\n```\n~~~\n[b](x.md)\n")).to eq([ [ 6, "x.md" ] ])
    end

    it "мітка з кодом лишається лінком, якщо сама не в code-span" do
      expect(hrefs("[`file.rb`](../file.rb)\n")).to eq([ [ 1, "../file.rb" ] ])
    end

    it "href у `<…>`, з титулом чи пробілами — той самий href, позначений прикрашеним" do
      got = described_class.relative_hrefs("[a](<x.md>) [b](x.md \"t\") [c]( x.md ) [d](x.md)\n")
      expect(got).to eq([ [ 1, "x.md", true ], [ 1, "x.md", true ], [ 1, "x.md", true ], [ 1, "x.md", false ] ])
    end
  end

  describe ".resolve" do
    it "відносно каталогу файлу, `/` — від кореня, без фрагмента й запиту, з декодуванням і буквальним `+`" do
      expect(described_class.resolve("docs/protocols/legal/b.md", "a.md#x")).to eq("docs/protocols/legal/a.md")
      expect(described_class.resolve("docs/page.md", "../tools/x/run.py?raw=1")).to eq("tools/x/run.py")
      expect(described_class.resolve("docs/protocols/legal/b.md", "/tools/x/run.py")).to eq("tools/x/run.py")
      expect(described_class.resolve("docs/page.md", "protocols/my%20sheet.md")).to eq("docs/protocols/my sheet.md")
      expect(described_class.resolve("docs/page.md", "a+b.md")).to eq("docs/a+b.md")
    end

    it "корінь репо — порожній рядок; вихід за корінь — nil" do
      expect(described_class.resolve("docs/page.md", "../")).to eq("")
      expect(described_class.resolve("docs/page.md", "../../outside.md")).to be_nil
    end
  end

  describe ".neighbour_form?" do
    it "лише голий слаг у вікі-сторінці й `../`-слаг у protocols, без прикрас — предмет сусідів" do
      expect(described_class.neighbour_form?(tracker, "00_07_Action_Plan_Tracker#a")).to be(true)
      expect(described_class.neighbour_form?("docs/protocols/legal/b.md", "../../01_01_Coaxial.md#a")).to be(true)
      expect(described_class.neighbour_form?(tracker, "00_07_Action_Plan_Tracker", true)).to be(false)
      expect(described_class.neighbour_form?(tracker, "00_07_Action_Plan_Tracker.md")).to be(false)
      expect(described_class.neighbour_form?("docs/page.md", "00_07_Action_Plan_Tracker")).to be(false)
      expect(described_class.neighbour_form?("docs/protocols/legal/b.md", "00_07_Action_Plan_Tracker")).to be(false)
      expect(described_class.neighbour_form?("docs/images/cad/x.md", "../../01_01_Coaxial.md")).to be(false)
    end
  end

  describe ".violations" do
    it "мертвий лінк — з файлом і рядком" do
      expect(v("docs/page.md", "ok\n[c](SECURITY_ASSURANCE_CASE)\n"))
        .to eq([ "docs/page.md:2: мертвий лінк `SECURITY_ASSURANCE_CASE` → `docs/SECURITY_ASSURANCE_CASE` (немає в git ls-files)" ])
    end

    it "шлях від кореня репо без `/` з верхнього docs/*.md мертвий у перегляді репо" do
      expect(v("docs/page.md", "[i](tools/x/run.py)\n").size).to eq(1)
      expect(v("docs/page.md", "[i](../tools/x/run.py) [j](/tools/x/run.py)\n")).to be_empty
    end

    it "живі файл, каталог, корінь репо, вміст субмодуля, `<…>`, титул і буквальний `+` проходять" do
      text = "[f](SECURITY_ASSURANCE_CASE.md) [d](../tools/x) [n](../NOTICE) [r](../) [s](../firmware/extern/lib/src/a.c) " \
             "[l](<../NOTICE>) [t](../NOTICE \"t\") [p](a+b.md)\n"
      expect(v("docs/page.md", text)).to be_empty
    end

    it "форма сусіда тут не судиться, навіть мертва" do
      expect(v(tracker, "[x](99_99_Nope)\n")).to be_empty
      expect(v("docs/protocols/legal/b.md", "[x](../../99_99_Nope.md)\n")).to be_empty
    end

    it "голий слаг у верхньому НЕ-вікі доці — предмет цього гейта: GitHub без `.md` дає 404 (00_06 §1, виняток)" do
      expect(v("docs/page.md", "[x](00_07_Action_Plan_Tracker)\n").size).to eq(1)
      expect(v("docs/page.md", "[x](00_07_Action_Plan_Tracker.md#a)\n")).to be_empty
    end

    it "прикрашену форму сусіда не судить жоден сусід — тож судить цей гейт" do
      expect(v(tracker, "[x](<99_99_Nope>)\n").size).to eq(1)
      expect(v("docs/protocols/legal/b.md", "[x](../../99_99_Nope.md \"t\")\n").size).to eq(1)
    end

    it "решта форм канон-лінка — предмет цього гейта: слаг без `../` у protocols мертвий, `.md` у верхньому — судиться" do
      expect(v("docs/protocols/legal/b.md", "[t](00_07_Action_Plan_Tracker)\n").first).to include("мертвий лінк")
      expect(v("docs/page.md", "[t](00_07_Action_Plan_Tracker.md) [n](99_99_Nope.md)\n").size).to eq(1)
    end

    it "слаг без `.md` живий лише з вікі-сторінки docs/NN_NN_*.md — деінде GitHub дає 404" do
      expect(v(tracker, "[t](./00_07_Action_Plan_Tracker)\n")).to be_empty
      expect(v("docs/images/cad/x.md", "[t](../../00_07_Action_Plan_Tracker)\n").size).to eq(1)
    end

    it "незакритий fence — порушення: решта файлу інакше мовчки не сканувалась би" do
      expect(v("docs/page.md", "ok\n```\n[a](dead.md)\n")).to eq([ "docs/page.md:2: незакритий fence — решта файлу не сканувалась" ])
    end

    it "вихід за межі репо — окреме повідомлення" do
      expect(v("docs/page.md", "[o](../../outside.md)\n").first).to include("за межі репозиторію")
    end

    it "ціль поза фільтром changes червоніє; під фільтром — ні, і для каталогу верхнього рівня теж" do
      filter = described_class.filter_regexps([ "docs/**", "**.md", "NOTICE", "tools/**" ])
      expect(v("docs/page.md", "[t](../tools/x/run.py) [d](../tools/) [n](../NOTICE)\n", filter: filter)).to be_empty
      narrow = described_class.filter_regexps([ "docs/**", "**.md" ])
      expect(v("docs/page.md", "[t](../tools/x/run.py)\n", filter: narrow).first).to include("поза фільтром")
    end
  end

  describe ".filter_regexps" do
    it "конверсія glob осі D2 guard_registry_sync: `**` перетинає `/`, `*` — ні" do
      star2, docs, py = described_class.filter_regexps([ "**.md", "docs/**", "tools/*.py" ])
      expect(star2.match?("tools/x/README.md")).to be(true)
      expect(docs.match?("docs/images/cad/x.png")).to be(true)
      expect(py.match?("tools/run.py")).to be(true)
      expect(py.match?("tools/x/run.py")).to be(false)
    end
  end
end
