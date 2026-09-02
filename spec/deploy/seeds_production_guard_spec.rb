# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../support/repo_root"

# [OPS.38] `db/seeds.rb` МУСИТЬ бути fail-closed на слоті `production`.
#
# 🔴 Чому це не «ще один пін», а носій відсутньої половини: заборона існувала від
# народження `lib/tasks/governance.rake` («Production must NOT call it under any
# circumstance») і від 2026-09-01 має код — але НУЛЬ гейтів. Видалення блоку не
# червонило б нічого, а сам файл починається з `delete_all` по 27 моделях.
#
# ⛔ Ціна асиметрична, і саме тому носій стоїть тут, а не в рунбуку: у Rails 8.1
# `db:schema:load` оголошено `task load: [:load_config, :check_protected_environments]`
# і на продовій базі падає само, а `db:seed` — `task seed: :load_config`, тобто БЕЗ
# гарда взагалі. Тож єдиний бар'єр між `db:seed` і живою базою — цей блок.
#
# ⚠️ ОГОЛОШЕНА СТЕЛЯ: спека судить ФОРМУ гарда статично (він у голові файлу, читає
# слот, зупиняє виконання), ніколи його поведінку в рантаймі — виконати `db/seeds.rb`
# у прикладі неможливо, бо перший же його рядок руйнівний. Поведінку двосторонньо
# перевірено мутацією при написанні (слот `production` → EXIT=1; слот `canopy` → EXIT=0),
# і саме тому тут пиняться ТРИ незалежні властивості: якби пін був один (наприклад
# «файл згадує DeploymentSlot»), його задовольнив би коментар.
RSpec.describe "db/seeds.rb production guard" do # rubocop:disable RSpec/DescribeClass
  subject(:source) { File.read(REPO_ROOT.join("db/seeds.rb")) }

  # Голова файлу = усе до першої руйнівної дії. Гард, що стоїть ПІСЛЯ неї, марний за
  # побудовою, тож позиція тут несуча, а не косметична.
  #
  # 🔴 Ріжемо по ВИКЛИКУ (`model.delete_all`), не по токену: сам гард ЦИТУЄ цю форму у
  # своєму повідомленні, тож наївний `split` обрізав би голову ВСЕРЕДИНІ гарда й дав
  # хибно-червоне. Той самий податок, що на будь-який текст про форму, яку він судить
  # (`ssot-maintenance` §Guard-craft #10a).
  let(:head) { source.split(/^\s*model\.delete_all/).first.to_s }

  it "зупиняє виконання на слоті production, а не лише попереджає" do
    expect(head).to match(/DeploymentSlot\.current\s*==\s*["']production["']/)
    expect(head).to match(/\babort\b/)
  end

  it "дискримінує СЛОТОМ, ніколи Rails.env — canopy теж біжить із RAILS_ENV=production" do
    guard = head[/if\s+SilkenNet::DeploymentSlot.*?\bend\b/m].to_s

    expect(guard).not_to be_empty
    expect(guard).not_to include('Rails.env')
  end

  it "стоїть ПЕРЕД першим руйнівним викликом — гард після нього нічого не рятує" do
    first_destructive = source.index(/^\s*model\.delete_all/)

    expect(first_destructive).not_to be_nil # інакше приклад вакуумний
    expect(source.index("DeploymentSlot")).to be < first_destructive
  end

# 🔴 Демо-пароль — ЛИШЕ локальний. Виміряно на живому canopy 2026-09-02: сід дійшов до кінця,
# і `admin@silkennet.com` (super_admin) приймав літерал із публічного репо крізь Cloudflare.
# Пін судить ФОРМУ джерела (жодного літерального `password:` у сіді, константа з
# `Rails.env.local?`-розвилкою); мутація «повернути літерал одному користувачу» → RED.
it "не сіє літерального пароля — поза local-середовищем демо-акаунти дістають випадковий" do
  expect(source).not_to match(/password:\s*["']/)
  expect(source).to match(/DEMO_PASSWORD\s*=\s*Rails\.env\.local\?\s*\?/)
end

  # Повідомлення — частина механізму, не ввічливість: гард без названої альтернативи
  # закінчується тим, що перший же оператор дописує собі обхід (`DISABLE_*`).
  it "називає, що робити НАТОМІСТЬ" do
    expect(head).to include("governance:bootstrap")
  end
end
