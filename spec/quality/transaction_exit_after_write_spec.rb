# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "prism"

# Носій інваріанта «не виходь із транзакції ПІСЛЯ запису» [OPS.33].
#
# 🔴 Чому цей гейт існує окремо, хоча коп для нього НАПИСАНИЙ: `Rails/TransactionExitStatement`
# вимкнений САМИМ гемом на Rails ≥ 7.2 — його джерело дослівно каже «transactions were restored
# to their historical behavior». На нашому `TargetRailsVersion: 8.1` він не здатен спрацювати
# ЖОДНОГО разу, тобто його зелене означало б «не перевірено», а не «чисто».
# ⚠️ І премісу гема спростовано рантайм-пробою на 8.1.3.1 (з контролем, бо без нього результат
# не відрізнити від зламаного приладу): `return` усередині `transaction do` **КОМІТИТЬ** щойно
# записане, тоді як `raise ActiveRecord::Rollback` у тому ж прогоні коректно відкочує.
# Отже небезпека жива, а стандартний інструмент структурно сліпий — саме той випадок, коли
# гейт не дублює копа, а заміняє неіснуючий.
#
# 🔑 РОЗРІЗНЮВАЧ. Наш повсюдний ідіом — «ГАРД ПЕРЕД записом»: `return false unless <умова>`
# на початку блоку. Він безпечний за побудовою: коміт порожньої транзакції є no-op.
# Небезпечна форма ДЗЕРКАЛЬНА — спершу мутація, потім вихід; тоді половина роботи
# фіксується назавжди, а викликач читає вихід як «нічого не сталось».
# Виміряно 2026-08-23 на всьому дереві: 43 блоки `transaction`/`with_lock`, 17 із виходом,
# небезпечних НУЛЬ. Тобто гейт народжується зеленим і стереже майбутнє — його живість
# доводить мутація, а не популяція порушень.
#
# 🔒 СТЕЛЯ — що цей гейт НЕ бачить. Мовчання тут означало б «перевірено».
#   1. **Мутацію крізь ВИКЛИК.** Бачаться лише літеральні імена з `MUTATORS`; метод-хелпер,
#      який пише всередині, і потім `return` — невидимі. Транзитивний граф викликів тут
#      не будується свідомо: ціна парсера непорівнянна з уловом на цьому дереві.
#   2. **Динамічні форми** — `send(:update!, …)`, `public_send`, метапрограмування.
#   3. **`throw`.** У дереві він живе двічі, обидва — AR-ідіом `throw :abort` у колбеку, який
#      фреймворк ловить і відкочує сам. Це ІНШИЙ клас, і включення дало б чистий шум.
#   4. **Транзакцію, відкриту не через `transaction`/`with_lock`** — напр. сирим SQL `BEGIN`.
#   5. **Порядок ВИКОНАННЯ.** Судиться порядок у ДЖЕРЕЛІ; мутація, до якої потік не доходить,
#      усе одно рахується. Це свідомий перекос у бік хибного позитиву: він голосний і
#      дешево знімається, тоді як хибний негатив на грошовому шляху — тихий.
#   6. **Чи мутація справді щось ЗАПИСАЛА.** `save`, що повернув `false`, нічого не пише —
#      але статично це невидиме, тож така пара все одно спрацює.
#
# ⚠️ ЩО НЕ Є ХИБНИМ ПОЗИТИВОМ, хоча виглядатиме ним для першого, кого гейт зупинить.
# Форма «записав і одразу повернув результат» (`update!` … `return rec`) на Rails 8.1
# ПРАЦЮЄ — коміт відбувається. Гейт її все одно флагує, і це вибір, не сліпота: намір
# автора («хочу закомітити») статично не відрізнити від наміру «хочу відкотити», а ціна
# помилки асиметрична — у другому випадку половина роботи фіксується назавжди, і
# викликач читає вихід як «нічого не сталось». Лік дешевий і робить намір видимим:
# винеси вихід ЗА блок (`transaction do … end; rec`). ⛔ Не послаблюй гейт під цю форму —
# саме так найдешевша реакція на незручний гейт перетворює його на декорацію.
# Сканер винесено з `describe` навмисно: класові методи прикладу недоступні, а константи
# всередині блоку — окремий коп. Модуль чистий (без Rails), тестується самим гейтом нижче.
module TxExitScanner
  module_function

  TX_OPENERS = %i[transaction with_lock].freeze

  # Літеральні писачі. `save`/`create`/`destroy`/`delete` без `!` теж тут: тихий незапис —
  # окремий клас, а нас цікавить сам ФАКТ мутації перед виходом.
  MUTATORS = %i[
    save save! create create! update update! update_column update_columns
    destroy destroy! destroy_all delete delete_all update_all insert_all insert_all!
    upsert_all increment! decrement! touch toggle! first_or_create! find_or_create_by!
  ].freeze

  Finding = Struct.new(:file, :write_line, :exit_line, :exit_src, keyword_init: true)

  # Збирає (мутації, виходи) з піддерева ОДНОГО блоку транзакції.
  #
  # Дві семантичні тонкощі, яких греп не має і які й вимагали AST:
  #   • `next`/`break` звʼязуються з НАЙБЛИЖЧИМ блоком, тож усередині вкладеного `each do`
  #     вони з транзакції НЕ виходять; `return` звʼязується з методом і виходить завжди.
  #   • мутація в ПРЕДИКАТІ умови, чия гілка містить вихід (`next unless rec.save`), є самим
  #     гардом, а не «записом перед виходом» — її діапазон реєструється як guard-зона.
  def scan(node, out, depth: 0, guards: [])
    return unless node.is_a?(Prism::Node)

    case node
    when Prism::IfNode, Prism::UnlessNode
      scan(node.predicate, out, depth: depth, guards: guards)
      inner = guards + [ node.predicate.location.start_offset..node.predicate.location.end_offset ]
      # Гілки беремо як «діти мінус предикат»: `IfNode` називає else-гілку `subsequent`,
      # а `UnlessNode` — `else_clause`, і покладатись на імена означало б ламатись від
      # мінора Prism. Тотожність — за `node_id`, бо `compact_child_nodes` віддає обгортки.
      node.compact_child_nodes
          .reject { |c| c.node_id == node.predicate.node_id }
          .each { |b| scan(b, out, depth: depth, guards: inner) }
      return
    when Prism::BlockNode
      # вкладений блок: `next`/`break` там наші — не наші
      node.compact_child_nodes.each { |c| scan(c, out, depth: depth + 1, guards: guards) }
      return
    when Prism::DefNode
      return # чужа область видимості — `return` там належить іншому методу
    when Prism::CallNode
      out[:writes] << node.location if MUTATORS.include?(node.name)
    when Prism::ReturnNode
      out[:exits] << [ node.location, guards ]
    when Prism::NextNode, Prism::BreakNode
      out[:exits] << [ node.location, guards ] if depth.zero?
    end

    node.compact_child_nodes.each { |c| scan(c, out, depth: depth, guards: guards) }
  end

  def findings_for(path)
    findings_in(File.read(path), path: path)
  end

  # Розділено, щоб гейт мав ВЛАСНІ піни на кожну вісь: без них «нуль порушень» на дереві
  # означало б «нуль перевірок», і мертву вісь було б не відрізнити від чистого дерева.
  def findings_in(src, path: "(probe)")
    result = Prism.parse(src)
    return [] unless result.success?

    blocks = []
    collect = lambda do |n|
      return unless n.is_a?(Prism::Node)

      blocks << n if n.is_a?(Prism::CallNode) && TX_OPENERS.include?(n.name) && n.block.is_a?(Prism::BlockNode)
      n.compact_child_nodes.each { |c| collect.call(c) }
    end
    collect.call(result.value)

    blocks.flat_map do |blk|
      out = { writes: [], exits: [] }
      scan(blk.block.body, out) if blk.block.body
      out[:exits].flat_map do |(exit_loc, guards)|
        out[:writes]
          .select { |w| w.start_offset < exit_loc.start_offset }
          .reject { |w| guards.any? { |g| g.cover?(w.start_offset) } }
          .map do |w|
            Finding.new(file: path, write_line: w.start_line, exit_line: exit_loc.start_line,
                        exit_src: src.lines[exit_loc.start_line - 1].to_s.strip[0, 70])
          end
      end
    end
  end
end

# Предметом гейта є ІНВАРІАНТ, а не клас-сканер, тож і `describe` іменний — інакше
# `SpecFilePathFormat` вимагав би назвати файл за допоміжним модулем, а не за правилом.
RSpec.describe "Вихід із транзакції після запису", type: :model do
  def scan_src(body)
    TxExitScanner.findings_in(body)
  end

  describe "ловить (RED-половина)" do
    it "запис, потім `return`" do
      expect(scan_src(<<~RB)).not_to be_empty
        ActiveRecord::Base.transaction do
          rec.update!(state: :done)
          return false if bail?
        end
      RB
    end

    it "запис, потім `next` на рівні самої транзакції" do
      expect(scan_src(<<~RB)).not_to be_empty
        ActiveRecord::Base.transaction do
          rec.save!
          next unless other?
        end
      RB
    end

    it "`return` із ВКЛАДЕНОГО блоку — він звʼязується з методом, тож із транзакції виходить" do
      expect(scan_src(<<~RB)).not_to be_empty
        ActiveRecord::Base.transaction do
          items.each do |i|
            i.update!(seen: true)
            return :bail if i.bad?
          end
        end
      RB
    end

    it "`with_lock` судиться так само, як `transaction`" do
      expect(scan_src(<<~RB)).not_to be_empty
        with_lock do
          update!(status: :pending)
          return false unless ok?
        end
      RB
    end
  end

  describe "НЕ ловить (GREEN-половина — без неї гейт вважав би дефектом наш повсюдний ідіом)" do
    it "гард ПЕРЕД записом" do
      expect(scan_src(<<~RB)).to be_empty
        ActiveRecord::Base.transaction do
          return false unless status_sent?

          update!(status: :done)
        end
      RB
    end

    it "мутація в ПРЕДИКАТІ гарда, модифікаторна форма (`next unless rec.save`)" do
      expect(scan_src(<<~RB)).to be_empty
        ActiveRecord::Base.transaction do
          next unless rec.save

          HardwareKeyService.provision(rec)
        end
      RB
    end

    it "та сама мутація-гард у БЛОКОВІЙ формі — розрізняє guard-зона, не однорядковість" do
      expect(scan_src(<<~RB)).to be_empty
        ActiveRecord::Base.transaction do
          unless rec.save
            next
          end
        end
      RB
    end

    it "`next` усередині ВКЛАДЕНОГО блоку — він виходить з ітерації, не з транзакції" do
      expect(scan_src(<<~RB)).to be_empty
        ActiveRecord::Base.transaction do
          items.each do |i|
            i.update!(seen: true)
            next if i.skip?
          end
        end
      RB
    end

    it "`return` усередині вкладеного `def` — чужа область видимості" do
      expect(scan_src(<<~RB)).to be_empty
        ActiveRecord::Base.transaction do
          rec.update!(x: 1)

          define_singleton_method(:helper) do
            def inner
              return :nope
            end
          end
        end
      RB
    end

    it "мутація ПОЗА транзакцією, вихід усередині" do
      expect(scan_src(<<~RB)).to be_empty
        rec.update!(x: 1)
        ActiveRecord::Base.transaction do
          return false unless ok?
        end
      RB
    end
  end

  describe "дерево цілком" do
    it "не виходить із `transaction`/`with_lock` після мутації — інакше half-work комітиться назавжди" do
    files = Dir[Rails.root.join("app/**/*.rb")] + Dir[Rails.root.join("lib/**/*.rb")]
    expect(files.size).to be > 100, "периметр порожній — гейт судив би ніщо"

    findings = files.flat_map { |f| TxExitScanner.findings_for(f) }

    expect(findings).to be_empty, lambda {
      findings.map do |f|
        rel = f.file.to_s.delete_prefix("#{Rails.root}/")
        "#{rel}:#{f.exit_line} — вихід (`#{f.exit_src}`) ПІСЛЯ запису на р.#{f.write_line}. " \
          "На Rails 8.1 такий вихід КОМІТИТЬ уже записане, тож транзакція фіксує половину " \
          "роботи, а викликач читає це як «нічого не сталось». Використай " \
          "`raise ActiveRecord::Rollback` (відкочує) або перенеси гард ПЕРЕД запис."
      end.join("\n")
    }
    end
  end
end
