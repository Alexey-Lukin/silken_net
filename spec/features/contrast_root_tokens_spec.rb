# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec/support/contrast_registry")

# [UI.3] Два КОРЕНЕВІ текстові токени тримають AA у ОБОХ темах — на кожній
# поверхні, яку вони реально отримують.
#
# 🔴 Чому це не можна довести ані арифметикою, ані статичним сканом. Порахувати
# пару «токен × поверхня» легко — але лише для поверхонь, які ти САМ перелічив, а
# фактичний фон приходить від батьківського компонента або з `<body>`
# ([`04_04 §9`](../../docs/04_04_Phlex_UI_and_Tailwind.md)). Перелік поверхонь є
# ГІПОТЕЗОЮ доти, доки його не віддав рендер: під час написання цього файлу
# арифметика на ПРИПУЩЕНОМУ стеку дала 1.12, а браузер — 1.17, бо під панеллю
# стояв `surface-base`, а не `surface`. Вердикт вижив, число — ні.
#
# 🔬 Що саме тут пінеться і чому такими числами:
#   · темна `--gaia-text-subtle` — альфа несе КОНТРАСТ, не лише приглушеність:
#     усі темні поверхні майже-чорні, тож обмеження односпрямоване й одна цифра
#     тримає всі поверхні одразу;
#   · світла `--gaia-text-subtle` — проміжне значення між Tailwind-500 і -600
#     свідомо: жоден палітровий «500» не тримає AA на `surface-sunken`, а «600»
#     дорівнює `--gaia-text-muted` і зламав би ієрархію;
#   · `--gaia-label` — у `.dark` рядка НЕ БУЛО взагалі, тож мітка полів читалась
#     значенням, що протекло з `:root`. Дефект був у ВІДСУТНОСТІ перевизначення.
#
# 🧱 ПЕРЕДУМОВА, без якої світла половина недосяжна В ПРИНЦИПІ, і вона тут не
# теорія: доки під цим токеном лежала сира тем-інваріантна чорна поверхня
# (`bg-zinc-950`, `bg-black/40`, градієнт `to-black`), один скаляр мусив бути
# ОДНОЧАСНО темнішим за стелю світлих `gaia`-поверхонь і світлішим за підлогу
# чорної панелі — смуга порожня, значення не існує. Тому міграція тих поверхонь
# на `gaia-*` є не сусідньою прибиранкою, а передумовою цього піна. Повернеш
# сиру поверхню під `text-subtle` — цей файл почервоніє, і це правильно.
#
# 🔒 Стелі (чесно й поіменно; зелений НЕ означає «сторінки доступні»):
#   · контур — чотири сторінки, а не всі; ✅ але перелік більше НЕ літерал тут:
#     він приходить із `ContrastRegistry::CONTOURS[:root_tokens]`, а сторож
#     популяції (`spec/quality/contrast_contour_registry_spec.rb`) не дає новому
#     маршрутові тихо випасти з виміру — доти саме це й було можливо;
#   · один розмір вікна — мобільна розмітка має власну (card-flip `td::before`);
#   · СТАНИ (`:hover`/`:focus-visible`/`::placeholder`/`:disabled`) не покриті —
#     статичний знімок їх не має за побудовою;
#   · судяться РІВНО ці два токени, не вся палітра;
#   · ✅ auth-родина (`sessions/new` · `passwords/{forgot,reset}`) має ВЛАСНИЙ
#     контур із 2026-08-18 — `spec/features/auth_contrast_spec.rb`. Розділення
#     не стилістичне: ті сторінки живуть ДО автентифікації, а цей контур цілком
#     стоїть за `before { sign_in_as }`, тож одним рядком вони сюди не входять.
#     ⚠️ Не «повертай» їх сюди за симетрією — і не читай їхню відсутність тут як
#     непокриття. Що там знайшлось (кнопка входу 2.28:1 у світлій, невидима
#     двом приладам одразу) — у шапці того файлу.
#
# ⚠️ Перед прогоном переконайся, що `public/assets/` НЕМАЄ — залишковий манифест
# тримає Propshaft на Static-резолвері й віддає застарілий CSS, тож прилад міряє
# знімок, а не дерево (стеля 3а в `spec/support/feature_helper.rb`; тут доти
# стояла зворотна порада — `assets:precompile`, — і вона цю ж пастку й ставить).
RSpec.describe "[UI.3] Кореневі текстові токени тримають AA в обох темах", :js do
  let(:organization) { create(:organization) }
  let(:password)     { "contrast-root-pass-1" }
  let!(:user) { create(:user, :admin, organization: organization, password: password) }
  let!(:cluster) { create(:cluster, organization: organization) }
  let!(:tree)    { create(:tree, cluster: cluster) }

  let(:tokens) { %w[--gaia-text-subtle --gaia-label] }

  # ⚠️ Шляхи звірені з `routes.rb`, а не вигадані: індекс дерев ВКЛАДЕНИЙ у
  # кластер, окремого `/trees` не існує — а промах туди дав би не помилку, а
  # числа сторінки 404.
  # ⚠️ Форма взята `firmwares`, а не `tree_families`: друга гейтована
  # `authorize_super_admin!`, тож для цього актора віддала б `Errors::Page` НА
  # ТОМУ Ж ШЛЯХУ — тобто мовчазний нуль пар при зеленому піні на шлях.
  def pages
    ContrastRegistry.paths_for(:root_tokens, cluster: cluster, tree: tree)
  end

  before { sign_in_as(user, password: password) }

  def resolved_token(name)
    page.evaluate_script(
      "getComputedStyle(document.documentElement).getPropertyValue('#{name}').trim()"
    )
  end

  # Поканальне порівняння, не рядкове: браузер вільний у формі серіалізації
  # (`rgba(52, 211, 153, 0.68)` ⟷ `rgba(52,211,153,.68)`).
  def same_colour?(one, two)
    a = SilkenNet::Contrast.parse(one)
    b = SilkenNet::Contrast.parse(two)
    a.first(3).map(&:round) == b.first(3).map(&:round) && (a[3] - b[3]).abs < 0.01
  rescue SilkenNet::Contrast::UnparseableColour
    false
  end

  def collect(theme)
    pages.flat_map do |path|
      values = nil
      harvest_contrast(path, theme: theme)[:pairs].filter_map do |pair|
        next if pair.ratio.nil?

        values ||= tokens.to_h { |t| [ t, resolved_token(t) ] }
        token = values.find { |_, v| v.present? && same_colour?(pair.colour, v) }&.first
        next unless token

        { token: token, path: path, pair: pair }
      end
    end
  end

  # 🔴 ЛІХТАР НА КОЖНУ СТОРІНКУ КОНТУРУ ОКРЕМО, і він тут не формальність.
  # Приклади нижче фільтрують пари до двох токенів, тож сторінка, яка не дала
  # ЖОДНОЇ пари, мовчки випадає з результату й лишає їх зеленими — тобто новий
  # член контуру може бути no-op'ом, і ніщо про це не скаже. `harvest_contrast`
  # уже пінить статус і `body_bg` (403/404 не пройдуть), але не питає, чи прилад
  # узагалі щось ПОБАЧИВ на цьому шляху. Тут питається саме це, поканально.
  # ⚠️ Судиться `measured_nodes`, а НЕ кількість пар: пари дедуплікуються за
  # (колір, стек, шрифт), тож на однорідній сторінці їх законно небагато, а от
  # нуль ВУЗЛІВ означає, що вимірювати не було чого (`ssot-maintenance`
  # §Guard-craft #72 — доводь на лічильнику, найближчому до ДЖЕРЕЛА).
  # ⛔ Не зводити до сумарного числа по контуру: сума ховає порожню сторінку за
  # рахунок сусідів, а питання тут саме по-сторінкове.
  it "кожна сторінка контуру справді ВИМІРЮЄТЬСЯ (порожня не рахується успіхом)" do
    empty = pages.filter_map do |path|
      nodes = harvest_contrast(path, theme: :dark)[:measured_nodes].to_i
      [ path, nodes ] if nodes < 5
    end

    expect(empty).to be_empty,
                     "сторінки контуру дали замало вимірюваних вузлів: #{empty.inspect} — " \
                     "прилад їх не бачить, і приклади нижче зелені саме тому"
  end

  # 🔴 ЛІХТАР НА МЕХАНІЗМ ЗВІЛЬНЕННЯ, а не на його декларацію. Реєстр оголошує
  # водяні знаки декорацією, і доти цю декларацію не застосовував НІХТО — три
  # поверхні описували механізм, якого не існувало (§Guard-craft #71 поверхом
  # вище: предмет був реальний, споживача не було). Тепер прилад читає токени з
  # `ContrastRegistry::DECORATIONS`, і цей приклад доводить, що звільнення
  # СПРАЦЬОВУЄ: `/trees/:id` несе `text-emerald-900/5`, тож кошик мусить бути
  # непорожній. Без нього «зелено» означало б лише «жоден контур водяного знака
  # не зустрів» — тобто порожньо, а не безпечно.
  it "оголошене звільнення декорацій СПРАЦЬОВУЄ на живій сторінці" do
    harvest = harvest_contrast("/trees/#{tree.id}", theme: :dark)
    excluded = harvest[:buckets]["excluded"]

    expect(excluded["declared_decoration"].to_i).to be_positive,
                                                    "жодного вузла не звільнено як декорацію — прилад не читає реєстр, " \
                                                    "або водяний знак на цій сторінці змінив клас (кошики: #{excluded.inspect})"
  end

  # 🔴 ВІСЬ СТАНІВ. Статичний знімок їх не має за побудовою, а приписаний у пункті
  # інструмент (`CSS.forcePseudoState`) я одного дня оголосив інертним — і помилявся:
  # інтерактивні поверхні дерева несуть `transition-*`, тож `getComputedStyle`
  # одразу після форсу віддає ще СТАРЕ інтерпольоване значення. Пауза міряється зі
  # сторінки (`settle_transitions!`), а сам форс самосвідчиться (`:hover`-матч).
  #
  # Судяться рівно НОВІ пари — ті, яких у спокої не було: базові вже покриті
  # прикладами вище, і повторне їх судження робило б цей приклад дублем.
  #
  # ⚠️ `:focus-visible` тут НЕ судиться: вимір дав нуль нових пар на всьому контурі
  # (кільце фокуса малюється `ring-*`, тобто тінню, а не парою текст/фон), тож
  # приклад був би зелений на порожній множині. `:disabled` виведений із-під 1.4.3
  # нормативно й відсівається самим приладом.
  %i[dark light].each do |theme|
    it "тема #{theme}: стан :hover не вводить провальної пари" do
      fresh = pages.flat_map do |path|
        calm = harvest_contrast(path, theme: theme)[:pairs].map { |x| [ x.colour, x.backdrop ] }
        harvest_contrast(path, theme: theme, force_state: :hover)[:pairs]
          .reject { |x| calm.include?([ x.colour, x.backdrop ]) }
          .map { |x| [ path, x ] }
      end

      # Ліхтар: нуль нових пар означає, що форс нічого не змінив — тобто приклад
      # атестує рівно те, що мав виміряти. Виміряно: контур дає їх кілька в обох
      # темах, тож порожня множина є ознакою поломки, не здоровʼя.
      expect(fresh).not_to be_empty,
                           "жодної нової пари під :hover — форс не подіяв або сторінки втратили інтерактивні поверхні"

      failures = fresh.reject { |_, x| x.passes }.map do |path, x|
        format("%s → %.2f (бар %.1f) «%s»", path, x.ratio, x.threshold, x.sample_text)
      end

      expect(failures).to be_empty, "hover провалює AA:\n  #{failures.uniq.join("\n  ")}"
    end
  end

  %i[dark light].each do |theme|
    it "тема #{theme}: жодна пара обох токенів не провалює свій поріг" do
      found = collect(theme)

      # 🔴 Самосвідчення, без якого приклад зелений на порожній множині — тобто
      # атестує рівно те, що мав виміряти. Обидва токени МУСЯТЬ зустрітись:
      # `--gaia-label` живе лише на формах, тож його відсутність означала б, що
      # контур утратив єдину сторінку, яка його носить.
      expect(found).not_to be_empty, "жодної пари — матчинг кольору зламаний, вимір недійсний"
      expect(found.map { _1[:token] }.uniq).to match_array(tokens),
                                               "контур утратив токен: знайдено лише #{found.map { _1[:token] }.uniq.inspect}"

      failures = found.reject { _1[:pair].passes }.map do |e|
        format("%s на %s → %.2f (бар %.1f) [%s] «%s»",
               e[:token], e[:pair].backdrop, e[:pair].ratio, e[:pair].threshold,
               e[:path], e[:pair].sample_text)
      end

      expect(failures).to be_empty, "AA провалено:\n  #{failures.uniq.join("\n  ")}"
    end
  end
end
