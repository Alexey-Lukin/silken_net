# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Гейт НЕЗМОНТОВАНОЇ ПОВЕРХНІ: railtie, який ніхто не вмикав рішенням, не сміє
# повернутись і мовчки опублікувати ендпоінти (`04_03 §1.3`, `00_07` ARCH.79).
#
# 🔴 Клас тут окремий і найтихіший: поверхня зʼявляється БЕЗ рішення когось її
# створити. Її не знайде ані аудит «чи всі наші ендпоінти захищені» (вона не
# наша), ані аудит мертвого коду (коду нема) — `rails/all` тягнув десять railtie
# пакетом, і три з них публікували 14 ingress-маршрутів плюс модель, що пише
# блоб у наше сховище на кожен вхідний лист, при відсутньому `app/mailboxes/`.
#
# ⚠️ Пускач, проти якого це стоїть, названий: `rails app:update` переписує
# `config/application.rb` і повертає `rails/all` без жодного червоного — саме
# тому носій пінить ПОВЕРХНЮ, а не текст конфігу.
#
# ⚠️ Стеля: гейт судить, що engine НЕ ЗАВАНТАЖЕНИЙ, і мовчить про Gemfile —
# гем лишається в дереві залежностей (він частина `rails`), тож «його немає в
# `Gemfile.lock`» цей приклад НЕ стверджує і стверджувати не може.
RSpec.describe "Незмонтовані engine не публікують поверхню", type: :request do
  # Liveness: без цього приклада порожній роутер зробив би головний пін
  # вакуумним — «нуль ingress-маршрутів» означало б «нуль маршрутів узагалі».
  it "має живий роутер, інакше решта прикладів нічого не доводить" do
    expect(Rails.application.routes.routes.size).to be > 100
  end

  it "не публікує ingress-маршрутів inbound-пошти" do
    ingress = Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s
      path if path.include?("action_mailbox") || path.include?("rails/conductor")
    end

    expect(ingress).to be_empty, <<~MSG
      Опубліковано ingress-поверхню, якої ніхто не вмикав рішенням:

      #{ingress.join("\n      ")}

      Найімовірніша причина — `rails/all` повернувся в `config/application.rb`
      (наприклад після `rails app:update`). Railtie перелічуються ЯВНО; дім
      рішення — `00_07` ARCH.79, механізм — коментар у самому `application.rb`.
    MSG
  end

  it "не вантажить engine, чиїх споживачів у дереві немає" do
    # ActionMailbox — нуль `app/mailboxes/`; ActionText — нуль `has_rich_text`.
    expect(defined?(ActionMailbox::Engine)).to be_nil
    expect(defined?(ActionText::Engine)).to be_nil
  end

  it "лишає змонтованими ті engine, що мають живих споживачів" do
    # GREEN-половина: гейт не про «менше railtie», а про «жодного без рішення».
    expect(defined?(ActiveStorage::Engine)).to eq("constant")
    expect(defined?(ActionCable::Engine)).to eq("constant")
  end
end
