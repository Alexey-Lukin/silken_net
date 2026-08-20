# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "rake"
require "tmpdir"

# Гейт НА ГЕЙТ: `gaia:lint_tokens` друкує «no raw Tailwind **colour utilities**
# detected» — заяву про ВСІ сирі кольорові утиліти. Цей приклад стереже, щоб
# вивіска не розходилася з реалізацією.
#
# 🔴 Народився з виміряної дірки, і доводилась вона не арифметикою, а мутацією
# (`00_07` UI.1, 2026-08-19). Регекс знав рівно підмножину палітри: `bg-` лише
# білий/чорний + пʼять НЕЙТРАЛЬНИХ родин; `text-` мав `white` і НЕ мав `black`;
# emerald різався по шкалах (`text-` 400…900, `border-` 700…900); носіїв
# `divide-`/`decoration-`/`stroke-`/`fill-` не існувало зовсім; іменований
# CSS-колір у дужках (`shadow-[0_0_8px_red]`) проходив повз hex-тест. Шість таких
# утиліт, вписаних у `app/views/shared/ui/empty_state.rb` — тобто в HARD-периметр,
# де правило звʼязує й де цей гейт є ЄДИНИМ носієм, — давали `✓ … EXIT=0`.
#
# ⚖️ Чому пін, а не довіра до регекса: без нього фікс оборотний одним комітом і
# нічим не сигналить. Гейт, чия єдина перевірка — «він же зелений», не
# відрізняється від гейта, що нічого не читає (`ssot-maintenance` §Guard-craft:
# «гейт, що під-імплементує оголошений контракт»). Пін мутований В ОБИДВА боки:
# кожен раніше сліпий діалект мусить ЧЕРВОНІТИ поіменно, а найближча ЗАКОННА
# форма — лишатись зеленою; без другої половини найдешевшою реакцією на
# майбутнє червоне буде послабити гейт (§Guard-craft #52).
#
# 🔒 Стелі — зелений ТУТ не означає, що поверхня чиста:
#   · Судиться ДІАЛЕКТ, ніколи ПЕРИМЕТР. Чи входить каталог у CI — окреме
#     речення, і його дім `.github/workflows/docs.yml` + `00_06 §3`.
#   · Судиться РОЗПІЗНАВАННЯ, ніколи ПРИДАТНІСТЬ. Токен при 1.1:1 тут пройде;
#     другий бік цієї стелі — браузерний збирач `spec/support/contrast_audit.rb`.
#   · Стелі самого гейта (інлайн `style:`, інтерпольований клас, клас із БД)
#     лишаються його стелями — цей пін їх НЕ закриває й не претендує.
#   · Перелік діалектів нижче — не популяція дерева, а набір ФОРМ. Нова форма
#     (ще один носій Tailwind) вимагає нового рядка тут, і нічого про це не
#     скаже: пін стереже те, що вже названо.
module GaiaLintProbe
  TASK = "gaia:lint_tokens"

  module_function

  # Прогін СПРАВЖНЬОГО таска, а не копії його регексів: другий дім патерна був би
  # рівно тим дрейфом, проти якого цей файл і стоїть.
  def run(scope)
    previous = Rake.application
    Rake.application = Rake::Application.new
    load Rails.root.join("lib/tasks/gaia_lint.rake").to_s

    buffer = StringIO.new
    original_stdout = $stdout
    status = 0
    begin
      $stdout = buffer
      with_scope(scope) { Rake::Task[TASK].invoke }
    rescue SystemExit => e
      status = e.status
    ensure
      $stdout = original_stdout
      Rake.application = previous
    end

    { status: status, out: buffer.string }
  end

  def with_scope(scope)
    previous = ENV.fetch("LINT_SCOPE", nil)
    scope.nil? ? ENV.delete("LINT_SCOPE") : ENV["LINT_SCOPE"] = scope.to_s
    yield
  ensure
    ENV["LINT_SCOPE"] = previous
  end

  # Дефолт таска — той самий шлях, яким його кличе CI (`docs.yml` не ставить
  # `LINT_SCOPE`), тож перевіряти треба саме ВІДСУТНІСТЬ змінної, не її значення.
  def run_default = run(nil)

  # Кожен рядок — ОДНА форма, щоб звіт назвав саме її. Так зняття однієї гілки
  # фікса червонить поіменний приклад, а не «щось у наборі».
  BLIND_DIALECTS = {
    "хроматична родина під `bg-`" => "bg-red-500",
    "хроматична родина під `text-`" => "text-red-400",
    "хроматична родина під `border-`" => "border-amber-800",
    "`text-black` (у `bg-` обидва, у `text-` був лише `white`)" => "text-black",
    "emerald під `bg-` (гілки не існувало взагалі)" => "bg-emerald-950",
    "emerald-шкала нижче 400 під `text-`" => "text-emerald-100",
    "emerald-шкала нижче 700 під `border-`" => "border-emerald-500",
    "носій `divide-`" => "divide-emerald-900",
    "носій `decoration-`" => "decoration-emerald-900",
    "носій `stroke-`" => "stroke-red-600",
    "носій `fill-`" => "fill-emerald-500",
    "іменований CSS-колір у arbitrary" => "shadow-[0_0_8px_red]",
    "сучасна колірна функція у arbitrary" => "bg-[oklch(0.7_0.1_150)]"
  }.freeze

  # Найближча ЗАКОННА форма до кожного діалекта вище. Пін, що не тримає цієї
  # половини, атестує лише власну суворість.
  LEGAL_FORMS = [
    "bg-gaia-surface", "text-gaia-text-strong", "border-gaia-border",
    "ring-gaia-primary-strong", "bg-status-danger-accent", "text-token-forest",
    "min-h-[60vh]", "tracking-[0.3em]", "stroke-[3]", "text-[40px]",
    "border-2", "shadow-lg", "divide-y", "fill-none", "outline-none",
    # Allowlist — лише те, що досі оголошене. Голий `bg-emerald-500` знято ще
    # сигнальною хвилею; пару `/10`+`/20` і `border-emerald-500/20` — порцією 10
    # (2026-08-20): останні носії мігрували на `bg-gaia-primary/10`, тож і вони
    # знову СИРИЙ діалект. Дот-грід auth-екранів — токен у arbitrary: сирим його
    # робив би лише `transparent`-стоп, і саме тому запис несе повний відбиток.
    "bg-[radial-gradient(var(--gaia-primary)_1px,transparent_1px)]",
    "shadow-[0_0_8px_#10b981]", "shadow-[0_0_8px_#ef4444]"
  ].freeze

  # Дужка з `url(`: колірне слово там є частиною ШЛЯХУ. Наївний підрядок ловив
  # `transparent` усередині колишнього домену (transparenttextures.com — хост
  # знято 2026-08-20, текстура самохоститься), а `white`/`black` живуть у
  # назвах файлів так само — приклад тримає обидві форми.
  LEGAL_URL = "bg-[url('carbon-weave-black-white.png')]"
  # Хвіст ідентифікатора збігається з іменем кольору (`…measu-RED`).
  LEGAL_IDENTIFIER = "@summary[:clusters_measured]"

  # Фікстура живе в tmpdir і зникає разом із ним: гейт читає СИРИЙ ТЕКСТ файла,
  # тож класи мусять стояти рядками, а не бути зібраними в рантаймі.
  def run_over(name, lines)
    Dir.mktmpdir("gaia-lint") do |dir|
      Pathname.new(dir).join(name).write(<<~RUBY)
        # frozen_string_literal: true
        class #{name.delete_suffix('.rb').split('_').map(&:capitalize).join}
          PROBE = [
        #{lines.map { |l| "      #{l.inspect}," }.join("\n")}
          ].freeze
        end
      RUBY
      run(dir)
    end
  end
end

RSpec.describe "[UI.1] gaia:lint_tokens розпізнає всі сирі колірні діалекти" do # rubocop:disable RSpec/DescribeClass
  describe "RED — раніше сліпий діалект мусить називатися поіменно" do
    let(:result) { GaiaLintProbe.run_over("blind_dialects.rb", GaiaLintProbe::BLIND_DIALECTS.values) }

    it "виходить із ненульовим кодом" do
      expect(result[:status]).to eq(1),
        "гейт мовчить про #{GaiaLintProbe::BLIND_DIALECTS.size} сирих утиліт; вивід:\n#{result[:out]}"
    end

    # Ліхтар популяції: вердикт про порожній набір — не вердикт. Тут він подвійний
    # — і про набір форм, і про те, що фікстуру взагалі прочитано.
    it "прочитав фікстуру, а не порожній набір" do
      expect(GaiaLintProbe::BLIND_DIALECTS.size).to be >= 13
      expect(result[:out]).to include("blind_dialects.rb")
    end

    GaiaLintProbe::BLIND_DIALECTS.each do |axis, klass|
      it "ловить #{axis} (#{klass})" do
        expect(result[:out]).to include(klass)
      end
    end
  end

  describe "GREEN — найближча законна форма лишається тихою" do
    let(:result) do
      GaiaLintProbe.run_over(
        "legal_forms.rb",
        GaiaLintProbe::LEGAL_FORMS + [ GaiaLintProbe::LEGAL_URL, GaiaLintProbe::LEGAL_IDENTIFIER ]
      )
    end

    it "виходить нулем і не називає жодного класу" do
      expect(result[:status]).to eq(0), "хибний позитив на законній формі:\n#{result[:out]}"
      expect(result[:out]).to include("no raw Tailwind colour utilities detected")
    end

    it "прочитав фікстуру, а не порожній набір" do
      expect(result[:out]).to match(/\(\d+ files scanned\)/)
      expect(GaiaLintProbe::LEGAL_FORMS.size).to be >= 18
    end
  end

  describe "HARD-периметр (дефолт таска) лишається зеленим" do
    # Ratchet: ані розширення діалекту, ані внесення нового домену не сміє
    # почервонити периметр, який гейтує CI. Виміряно ПЕРЕД кожним внесенням.
    let(:result) { GaiaLintProbe.run_default }

    it "не має жодного сирого колірного класу" do
      expect(result[:status]).to eq(0), "HARD-периметр почервонів:\n#{result[:out]}"
    end

    # 🔴 Ліхтар популяції на САМОМУ периметрі, а не лише на фікстурах. Без нього
    # запис у `default_scopes`, що вказує на неіснуючий чи перейменований каталог,
    # мовчки зменшує множину, і ✓ починає атестувати менше, ніж учора — а
    # повідомлення гейта при цьому не змінюється жодним словом.
    it "читає ВЕСЬ дефолт, а не саму `shared/`" do
      scanned = result[:out][/\((\d+) files scanned\)/, 1].to_i
      shared_only = GaiaLintProbe.run("app/views/shared/")[:out][/\((\d+) files scanned\)/, 1].to_i

      expect(shared_only).to be > 0
      expect(scanned).to be > shared_only,
        "дефолт прочитав #{scanned} файлів проти #{shared_only} у самій `shared/` — " \
        "запис у `default_scopes` резолвиться в порожньо"
    end
  end
end
