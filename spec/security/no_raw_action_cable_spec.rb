# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Заборона `ActionCable.server.broadcast` у застосунку. Це не стильова
# преференція — це вісь АВТОРИЗАЦІЇ.
#
# 🔴 Асиметрія, заради якої гейт існує: `turbo_stream_from` віддає клієнту
# ПІДПИСАНЕ ім'я стріму, і отримати його може лише той, кому сторінка вже
# відрендерилась — тобто підписка успадковує Pundit/скоупінг тієї сторінки.
# Сирий `ActionCable.server.broadcast("org_#{id}_alerts", …)` не має поверхні
# авторизації ВЗАГАЛІ: ім'я — довільний рядок, а всі наші ID послідовні bigint,
# тож канал тривіально перебирається.
#
# 🔴 І «каналів у нас немає, отже безпечно» — хибно, перевірено 2026-07-27:
# `ActionCable::Engine` монтує `/cable` САМ, в `after_initialize`, без рядка в
# `routes.rb`; `internal: true` ховає його від `bin/rails routes`, а `GET /cable`
# віддає 404 як неіснуючий шлях. Тобто «немає mount» — не факт, а артефакт
# двох способів подивитись. Плюс `solid_cable` пише КОЖЕН broadcast у
# `solid_cable_messages` — окрема логічна БД, але той самий інстанс і ті самі
# креденшели, retention доба: payload лежить читабельним навіть без жодного
# WebSocket-клієнта. Саме тому «мертвий» raw-broadcast — не нуль ризику.
#
# 🔒 Стеля: гейт бачить ЛИШЕ літеральний виклик у не-коментованому рядку
# `app/**` та `lib/**`. Виклик, зібраний через `send`/рядкову інтерполяцію,
# сюди не потрапляє; так само не покрито власний `ApplicationCable::Channel`,
# якби його завели — саме він і був би реальною активацією IDOR (тоді потрібен
# інший гейт: `stream_from` з інтерпольованим параметром).
RSpec.describe "no raw ActionCable broadcasts" do # rubocop:disable RSpec/DescribeClass
  let(:scanned_files) { Dir[Rails.root.join("{app,lib}/**/*.rb")].sort }

  let(:offenders) do
    scanned_files.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, idx|
        next if line.lstrip.start_with?("#")
        next unless line.include?("ActionCable.server.broadcast")

        "#{Pathname.new(path).relative_path_from(Rails.root)}:#{idx + 1}"
      end
    end
  end

  # Без цього «0 порушень» могло б означати «glob нічого не знайшов».
  it "is a live check (the app tree is non-empty and scannable)" do
    expect(scanned_files.size).to be > 100,
      "сканер знайшов замало файлів — glob дивиться не туди"
  end

  it "routes every realtime update through a signed Turbo stream" do
    expect(offenders).to be_empty, <<~MSG
      сирий ActionCable-broadcast не має поверхні авторизації — ім'я каналу це
      довільний рядок, а наші ID послідовні. Використовуй
      `Turbo::StreamsChannel.broadcast_*_to` + `turbo_stream_from` (`04_04 §8.1`):
      підписане ім'я стріму дістається лише тому, кому сторінка вже відрендерилась.
      Знайдено: #{offenders.join(', ')}
    MSG
  end
end
