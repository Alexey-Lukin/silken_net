# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [TEST.7] Кожен JS-модуль мусить їхати з НАШОГО походження.
#
# 🔴 Чому це окремий сторож, а не рядок у код-рев'ю. Доти `leaflet` пінився на
# `ga.jspm.io`, і ціна виявилась не «зайвий зовнішній запит», а НЕВІДТВОРЮВАНІСТЬ:
# `map_controller.js` робить СТАТИЧНИЙ `import L from "leaflet"` на верхньому
# рівні модуля, тож коли CDN недосяжний, падає не `connect()`, а завантаження
# всього модуля — Stimulus навіть не реєструє контролер. Виміряно блокуванням
# домену: із живим CDN у застосунку 8 контролерів і `.leaflet-pane` = 7, із
# мертвим — 7 контролерів (зникає саме `map`) і 0. Саме тому два прогони того
# самого дерева в різних сесіях давали 7 і 0, а причину тричі шукали в коді.
#
# ⚠️ Пін на «мапа будується» цього класу НЕ стереже: доки CDN живий, він зелений
# і з зовнішнім піном. Стереже лише інваріант ПОХОДЖЕННЯ — тобто цей файл.
#
# Дзеркальна половина — CSP: `script_src :self` є ЗАЯВОЮ, що зовнішніх модулів
# немає. Якщо пін повернуть, не чіпаючи CSP, браузер у продакшені мовчки
# заблокує модуль (політика enforced при `CSP_ENFORCE=true`) — тобто дефект
# приїде саме туди, де його найдорожче ловити. Тому обидві половини перевіряємо
# разом: розійтись вони не мають права.
RSpec.describe "Importmap locality", type: :model do
  let(:packages) { Rails.application.importmap.packages }

  it "pins every module to a local path, never to an external URL" do
    external = packages.filter_map do |name, package|
      path = package.try(:path).to_s
      [ name, path ] if path.match?(%r{\A[a-z][a-z0-9+.-]*://}i) || path.start_with?("//")
    end

    expect(external).to be_empty,
      "Зовнішній importmap-пін: #{external.inspect}. " \
      "Модуль із чужого домену робить сторінку залежною від його аптайму, а " \
      "статичний import на верхньому рівні валить ВЕСЬ Stimulus-контролер, " \
      "не лише свою фічу. Завантаж пакет локально: bin/importmap pin <name>."
  end

  it "keeps script-src free of external origins, matching those local pins" do
    script_src = Rails.application.config.content_security_policy.directives["script-src"]

    external = Array(script_src).grep(%r{\Ahttps?://}i)

    expect(external).to be_empty,
      "CSP script_src впускає зовнішні джерела #{external.inspect}, хоча всі " \
      "importmap-піни локальні. Або пін повернули й забули тут, або дозвіл " \
      "переживає свою причину — обидва стани брехливі."
  end
end
