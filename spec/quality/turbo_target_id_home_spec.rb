# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [UI.4] Гейт осі TARGET-ID: адресу цілі Turbo-броадкасту називає ОДИН дім, а не
# обидва боки тракту рукою.
#
# 🔴 Чому саме ця вісь, а не імена стрімів (ті вже мають дім `TurboStreams::Name`):
# у неї Є shipping-record, а в імен його немає. Два з трьох відомих випадків
# «продюсер і підписник на різних адресах» були саме розходженням target-id
# (`transaction_{id}` проти `dom_id`, `actuator_card_{id}` проти `actuator_{id}`),
# і жоден дім ІМЕН їх не накриває за побудовою.
#
# 🔴 Чому гейт, а не ревʼю: розходження такої пари НЕ МАЄ СИМПТОМУ. Turbo мовчки
# ковтає `replace`/`remove` у ціль, якої немає в DOM, тож зламаний тракт виглядає
# як живий — сторінка просто не оновлюється, і ніхто не бачить помилки. А спеки
# тут третій шар дублювання: кожна пінить лише ОДИН бік, тож координовано-хибна
# правка (продюсер + його спека, без рендерера) лишається зеленою.
#
# 🔒 Стеля, названа явно — інакше зелений колір читатиметься ширше, ніж є:
#   · Гейт лексичний: він бачить ЛІТЕРАЛ із відомим префіксом, а не «будь-яку
#     рукописну адресу». Нова родина цілей не захищена, доки її префікс не
#     додано сюди — саме тому реєстр курований, а не деривований.
#   · Він НЕ перевіряє, що обидва боки кличуть дім на однакових аргументах:
#     `dom_id(@wallet.id)` ⊥ `dom_id(@tree.id)` для нього однакові. Це вісь
#     «правильний аргумент», і її тримає читання.
#   · Він мовчить про те, чи ціль узагалі рендериться на живому МАРШРУТІ —
#     четверта ланка контракту (`04_04 §8.1`), яку жоден статичний скан не бачить.
# Форма-дзеркало `ModelMessageLocalization`: реєстр і скан живуть у модулі, а не в
# `describe` — інакше константа тече в глобальний неймспейс усього прогону.
module TurboTargetIdHome
  # Префікс → файл, якому НАЛЕЖИТЬ його деривація (єдиний, де літерал легальний).
  HOMED_TARGETS = {
    "wallet_balance_frame_" => "app/views/components/wallets/balance_frame.rb",
    "ota_progress_"         => "app/views/components/firmwares/ota_progress_bar.rb",
    "map_node_"             => "app/views/components/dashboard/map_node.rb",
    "telemetry_feed"        => "app/views/components/telemetry/live_stream.rb",
    "feed_placeholder"      => "app/views/components/telemetry/live_stream.rb",
    "maintenance_photos_"   => "app/views/components/maintenance/photo_gallery.rb",
    "photos_grid_page_"     => "app/views/components/maintenance/photo_gallery.rb"
  }.freeze

  module_function

  def scanned_files
    Dir[Rails.root.join("app/**/*.rb")].sort
  end

  def offenders
    HOMED_TARGETS.flat_map do |prefix, home|
      scanned_files.filter_map do |path|
        rel = Pathname.new(path).relative_path_from(Rails.root).to_s
        next if rel == home

        File.readlines(path).each_with_index.filter_map do |line, idx|
          next if line.lstrip.start_with?("#")
          next unless line.include?(%("#{prefix}))

          "#{rel}:#{idx + 1} — літерал «#{prefix}…» поза домом #{home}"
        end
      end.flatten
    end
  end
end

RSpec.describe "Turbo target-id has one home" do # rubocop:disable RSpec/DescribeClass
  let(:offenders) { TurboTargetIdHome.offenders }

  it "keeps every homed target literal inside its own home" do
    expect(offenders).to be_empty, <<~MSG
      Рукописний target-id поза його домом:

      #{offenders.join("\n      ")}

      Обидва боки тракту мусять кликати ОДИН дім (метод класу компонента, який
      ціль рендерить, або константу для статичного синглтона). Інакше розходження
      адрес не має симптому: Turbo мовчки ковтає заміну в неіснуючу ціль, і тракт
      виглядає живим, поки сторінка не оновлюється.
    MSG
  end

  # 🔴 Ліхтар на власну множину: без нього «нуль порушень» означало б і «нуль
  # перевірок» — досить перейменувати дім, і гейт замовкне назавжди на порожньому
  # скані (§Guard-craft #61: якщо перемога виглядає як порожня множина, живість
  # доводить ДЕТЕКТОР, а не популяція).
  it "still resolves every declared home" do
    missing = TurboTargetIdHome::HOMED_TARGETS.values.uniq.reject { |home| File.exist?(Rails.root.join(home)) }

    expect(missing).to be_empty, "дім зник або переїхав: #{missing.join(', ')}"
  end

  it "sees the literal it forbids — the home itself still derives it" do
    TurboTargetIdHome::HOMED_TARGETS.each do |prefix, home|
      body = File.read(Rails.root.join(home))

      expect(body).to include(%("#{prefix})),
                              "дім #{home} більше не містить «#{prefix}…» — гейт перевіряє порожнечу"
    end
  end
end
