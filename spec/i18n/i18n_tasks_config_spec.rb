# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require "erubi"

# Пін на шов між ДВОМА конфігами, які мусять говорити про один каталог локалей:
# рантайм-Rails (`config.i18n.*`) і CI-гейт парності (`config/i18n-tasks.yml`).
#
# Чому це окремий гейт, а не «і так очевидно»: обидва боки зелені поодинці навіть
# коли розійшлись. Локаль, додана в Rails, але не вписана в i18n-tasks, просто
# випадає з перевірки парності — CI лишається зеленим, а мова тихо не перевіряється
# ніколи. Саме так lv/lt колись і жили [I18N.1]. Це той самий клас, що в
# `ssot-maintenance` §Guard-craft #6: кожен гейт звіряє ОДНОРІДНУ пару й сліпий
# до шва між шарами.
#
# `locales:` деривується з `application.rb` через Erubi, тож у здоровому стані
# розбігтися нічим — цей файл стереже саме РЕГРЕС деривації (хтось вписав список
# назад літералом). `base_locale` навмисно НЕ деривується: він читається як
# самостійне рішення («база = мова вихідників»), тож тримається піном, не кодом.
#
# 🔒 Стеля: перевіряється ЗБІГ НАБОРІВ, не політика повноти. Яка локаль
# «завершена» (HARD-парність) проти «наздоганяє» (fallback легальний) — рішення
# рівня CI-прапорця `-l`, дім опису `04_04 §12.10`; сюди воно не входить.
RSpec.describe "config/i18n-tasks.yml ⟷ Rails i18n config" do # rubocop:disable RSpec/DescribeClass
  # Читаємо тим самим шляхом, що й сам гем (`Configuration#file_config`):
  # Erubi → eval → YAML. Власний парсер тут був би третьою правдою.
  let(:file_config) do
    path = Rails.root.join("config/i18n-tasks.yml")
    Dir.chdir(Rails.root) { YAML.load(eval(Erubi::Engine.new(File.read(path, encoding: "UTF-8")).src)) } # rubocop:disable Security/Eval
  end

  it "derives the very same locale set Rails serves" do
    expect(file_config["locales"].map(&:to_sym)).to match_array(I18n.available_locales)
  end

  # Якщо база гейта і термінус fallback-ланцюга розійдуться, парність міряла б
  # повноту проти мови, на яку ніхто не падає.
  it "uses the fallback terminus as its base locale" do
    expect(file_config["base_locale"].to_sym).to eq(I18n.default_locale)
  end

  # Без цього «набори збіглись» могло б означати «обидва порожні».
  it "is a live check (both sides non-empty)" do
    expect(file_config["locales"]).not_to be_empty
    expect(I18n.available_locales).not_to be_empty
  end
end
