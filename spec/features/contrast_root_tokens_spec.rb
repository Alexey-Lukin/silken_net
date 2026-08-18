# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

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
#   · контур — чотири сторінки, а не всі: реєстру сторінок ще немає (`00_07` UI.3);
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
    [ "/dashboard", "/clusters/#{cluster.id}/trees", "/trees/#{tree.id}", "/firmwares/new" ]
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
