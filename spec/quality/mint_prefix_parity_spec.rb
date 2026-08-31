# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../support/repo_root"

# 🔴 Префікси `identifier`, з яких субграф деривує ПРИРОДУ емісії, продубльовані в
# двох мовах — і доти обидва боки лише КОМЕНТУВАЛИ один на одного («грепай DOC-T.89»).
#
# Чому це money-path, а не косметика. `mintKindOf` класифікує подію за префіксом, і
# `GROWTH` є **ВІДСУТНІСТЮ мітки**, а не власною міткою — на дроті її немає. Отже
# розходження тихе **зі зсувом У БІК КЛЕЙМУ**: будь-який нерозпізнаний субграфом
# префікс мовчки падає в «це вуглецевий клейм», тобто помилка завищує саме те число,
# яке читає ESG-покупець і зовнішній аудитор (`totalMintedGrowth`). Зламатись можуть
# обидва боки: Rails перейменує префікс — субграф перестане його бачити; субграф
# звузить літерал — те саме. Жоден компілятор пари не звіряє, бо мови різні, а
# `graph build` судить ТИПИ мапінгу, ніколи семантику (OPS.34, оголошена стеля).
#
# 🔒 CEILING, названа, щоб зелене не читалось ширше: спека звіряє **ЛІТЕРАЛИ**
# констант, ніколи логіку, що їх вживає. Так само поза скоупом — чи ВСІ природи
# емісії мають префікс: `GROWTH` його не має за конструкцією дроту.
#
# 🔴 АЛЕ ця стеля до 2026-08-31 несла хибну ПОЛОВИНУ, і хибною була та, що
# призначала носія: тут стояло «порядок перевірок у `mintKindOf` … стереже
# КОМЕНТАР У САМОМУ МАПІНГУ, не цей файл», тоді як `subgraph/src/mapping.ts`
# від тієї ролі прямо відхрещується — мутація 2026-08-28 [OPS.36] показала, що
# реверс двох `if` лишає всі девʼять тестів зелені, тож коментар не стереже
# нічого. Два файли вказували один на одного протилежними стрілками, і кожен
# окремо читався розумно. **Чинний розподіл: порядок у `mintKindOf` не несучий
# САМ ПО СОБІ — його робить безпечним вісь «жоден префікс не є ПОЧАТКОМ іншого»,
# і стереже її ЦЕЙ файл** (приклад нижче). Порядок справді несучий у сусідньому
# `subjectDidOf` (послідовне зняття), і там та сама мутація валить тест поіменно.
#
# 🔴 І передумова, без якої гейт неможливий: `TAX_BATCH_` на Rails-боці жив ГОЛИМ
# літералом усередині `build_batch_arrays`, тож був поза будь-яким піном за побудовою
# (§Guard-craft #97 — наш пін-двигун читає `NAME = value`). Витягнення константи —
# частина ЦЬОГО ж заходу, а не сусідній рефактор.
# Обидва боки читаються з ДЖЕРЕЛА однією формою `NAME = "value"`; власної копії значень
# ця спека не тримає — інакше вона стала б ТРЕТІМ домом, і послаблення на будь-якому
# боці лишалось би тут зеленим (guard-craft: expectation must not re-run the logic
# under test — і тим паче не дублювати її предмет).
module MintPrefixParity
  RUBY_SOURCE = REPO_ROOT.join("app/services/blockchain_minting_service.rb")
  TS_SOURCE   = REPO_ROOT.join("subgraph/src/mapping.ts")
  NAMES       = %w[INSURANCE_MINT_PREFIX TAX_BATCH_PREFIX].freeze

  def self.ruby_const(name)
    RUBY_SOURCE.read[/^\s*#{name}\s*=\s*"([^"]*)"/, 1]
  end

  def self.ts_const(name)
    TS_SOURCE.read[/^\s*const\s+#{name}\s*(?::\s*string\s*)?=\s*"([^"]*)"/, 1]
  end
end

RSpec.describe MintPrefixParity, type: :quality do
  def ruby_const(name) = described_class.ruby_const(name)
  def ts_const(name)   = described_class.ts_const(name)

  # 🔦 Ліхтар ПЕРЕД порівнянням: витягачі мовчазні за побудовою — регекс, що перестав
  # матчити, віддає `nil`, і `nil == nil` було б «паритетом» над порожнечею. Тому
  # непорожність кожного боку пінується ОКРЕМО від їхньої рівності.
  MintPrefixParity::NAMES.each do |name|
    it "витягає `#{name}` з ОБОХ джерел (порожній витяг = вакуумний паритет)" do
      # ⚠️ Без Rails тут немає `be_present` — джоба `docs_check` не тягне `:environment`.
      expect(ruby_const(name)).to be_a(String)
      expect(ruby_const(name)).not_to be_empty
      expect(ts_const(name)).to be_a(String)
      expect(ts_const(name)).not_to be_empty
    end

    it "`#{name}` збігається побайтово між Rails і мапінгом субграфа" do
      expect(ts_const(name)).to eq(ruby_const(name)),
                               "Rails каже #{ruby_const(name).inspect}, subgraph — #{ts_const(name).inspect}. " \
                               "Розходження ТИХЕ й зі зсувом у бік клейму: нерозпізнаний префікс падає в GROWTH."
    end
  end

  # Дзеркальна вісь: префікси не сміють бути ПРЕФІКСАМИ один одного в неочікуваний бік.
  # `TAX_BATCH_INS_<did>` легальний і саме тому `mintKindOf` перевіряє TAX першим; а от
  # якби `INS_` став префіксом `TAX_BATCH_`, порядок перестав би рятувати й класифікація
  # поїхала б при обох боках, «згодних» побайтово.
  it "жоден префікс не є початком іншого — інакше порядок перевірок перестає рятувати" do
    ins = ruby_const("INSURANCE_MINT_PREFIX")
    tax = ruby_const("TAX_BATCH_PREFIX")

    expect(tax).not_to start_with(ins)
    expect(ins).not_to start_with(tax)
  end
end
