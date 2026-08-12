# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Носій одного інваріанта: спільна пагінаційна фікстура віддає СПРАВЖНІЙ
# `Pagy::Offset`, а не двійника з дописаним API (`04_06 §B.2` BP #14, десята вісь).
#
# Народився з `TEST.12`: попередній `OpenStruct` оголошував `vars` (методу з таким
# іменем на `Pagy::Offset` немає), робив ПУБЛІЧНИМ `series` (у гема `protected`) —
# і, найважливіше, приймав `count` та `last` як незалежні поля, тоді як гем виводить
# `last` із `count`/`limit`. Тобто фікстура вміщала стан, недосяжний за побудовою.
# Дописування повз RSpec mock-API не бачить `verify_partial_doubles`, тож така
# підміна переживає мажорний бамп гема мовчки — саме так Pagy 43 колись і проїхав.
#
# Хелпер годує ~20 компонентних спек, тож регресія тут тиха й широка водночас.
RSpec.describe "[TEST.12] спільна пагінаційна фікстура — справжній Pagy" do # rubocop:disable RSpec/DescribeClass
  include PhlexComponentHelper

  it "віддає справжній Pagy::Offset, а не двійника з дописаним API" do
    pagy = mock_pagy(count: 63, last: 3)

    expect(pagy).to be_a(Pagy::Offset)
    # `last` не задано — воно ВИВЕДЕНЕ, тож суперечити `count` не може.
    expect(pagy.last).to eq(3)
    # Обидва — сліди попередньої підміни: перший метод гем не має взагалі,
    # другий у нього `protected`, і саме публічність була дописана фікстурою.
    expect(pagy).not_to respond_to(:vars)
    expect(pagy).not_to respond_to(:series)
  end
end
