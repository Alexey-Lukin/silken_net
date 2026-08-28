# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require_relative "../support/repo_root"

# 🔴 [UNI.3] Кожен ВЕНДОРЕНИЙ компонент мусить бути НАЗВАНИЙ у `THIRD_PARTY_NOTICES`.
#
# Чому саме тут і саме ця властивість. Inbound-обовʼязок (нести copyright-нотіс,
# нести текст ліцензії) формулюється ПРОЗОЮ ліцензії, і жоден гейт його не
# перевірить. Але його передумова формальна й статично видима: компонент, якого
# в інвентарі НЕМАЄ, не має і шансу бути перевіреним людиною.
#
# 🔴 І дірка, яку це закриває, народилась із ДВОХ правильних рішень (виміряно
# 2026-08-28): `THIRD_PARTY_NOTICES` збирається з МАНІФЕСТІВ (`license_finder` для
# гемів, npm/forge для контрактів, conda для tools), а `scripts/spdx_headers.rb`
# свідомо DENY-листить `vendor/` — бо ставити НАШ SPDX на чужий файл не можна.
# Кожне окремо праве; разом вони лишили поверхню, яку ми РЕАЛЬНО поширюємо
# байтами, без жодного ока: кореневого `package.json` не існує взагалі, Leaflet
# приходить голим `pin "leaflet"` в `importmap.rb`, тож маніфеста, який його
# називає, немає ніде. Leaflet і JetBrains Mono лежали в дереві з нулем згадок в
# обох нотіс-файлах, а `leaflet.css` (661 рядок) і 5 спрайтів не несли й власного
# copyright, тоді як BSD-2-Clause вимагає, щоб нотіс ЇХАВ із поширенням.
#
# 🔒 СТЕЛІ, названі, щоб зелене не читалось ширше:
#   · гейт судить НАЗВАНІСТЬ компонента, ніколи виконання умов його ліцензії й
#     ніколи правильність названої ліцензії — і те, й те лишається читанням;
#   · він бачить лише `vendor/` (тека, яку ми поширюємо байтами). Сабмодулі
#     (`firmware/extern/**`, `tools/cad/extern/**`) — це gitlink'и, тобто
#     покажчики, і їхній дім в інвентарі окремий;
#   · імʼя компонента виводиться зі ШЛЯХУ, тож перейменування теки без правки
#     інвентарю червонить — це навмисне: інвентар ключується на тому ж імені.
module VendoredComponentInventory
  INVENTORY = "THIRD_PARTY_NOTICES"

  # Файли, що не є вендореним вмістом: наші ж нотіс-покажчики й `.keep`.
  NON_CONTENT = /(\A|\/)(\.keep|LICENSE|LICENSE-.*\.txt|NOTICE)\z/

  # `vendor/javascript/leaflet.js` → "leaflet"
  # `vendor/assets/fonts/jetbrains-mono/x.woff2` → "jetbrains-mono"
  # `vendor/assets/stylesheets/leaflet/images/marker.png` → "leaflet"
  #
  # ⚠️ Компонент береться з ПЕРШОГО сегмента після типу, а не з передостаннього.
  # Перша редакція брала `parts[-2]` і на спрайтах Leaflet повертала «images» —
  # а гейт із нею був ЗЕЛЕНИЙ, бо слово «images» випадково збіглося підрядком із
  # рядком `images/*.png` в інвентарі. Тобто хибна деривація давала хибний
  # компонент, який хибно ж і знаходився: зелень із неправильної причини.
  # Спіймано перерахунком множини ВРУЧНУ, не прогоном.
  def self.component_for(path)
    parts = path.split("/")
    return parts[3] if parts[1] == "assets" && parts.length >= 5

    File.basename(parts[2].to_s, ".*")
  end

  def self.components
    tracked = Dir.chdir(REPO_ROOT) { `git ls-files vendor/`.split("\n") }
    tracked.reject { |f| f.match?(NON_CONTENT) }.map { |f| component_for(f) }.uniq.sort
  end
end

RSpec.describe VendoredComponentInventory do
  let(:inventory) { REPO_ROOT.join(described_class::INVENTORY).read }

  it "ліхтар: у дереві справді є вендорений вміст" do
    # Без цього порівняння нижче стало б вакуумним: порожня множина «проходить»
    # проти будь-якого інвентарю, і гейт зеленів би саме тоді, коли осліп.
    expect(described_class.components).not_to be_empty
  end

  it "кожен вендорений компонент названий в інвентарі" do
    missing = described_class.components.reject do |c|
      inventory.downcase.include?(c.downcase)
    end

    expect(missing).to be_empty,
                       "вендоровані компоненти без запису в #{described_class::INVENTORY}: " \
                       "#{missing.join(', ')}. Ми поширюємо ці байти, тож inbound-обовʼязок " \
                       "(нести copyright-нотіс і текст ліцензії) лежить на нас — а компонент, " \
                       "якого немає в інвентарі, ніхто й не перевірить [UNI.3]"
  end
end
