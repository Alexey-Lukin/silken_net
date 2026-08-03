# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.25] Пін на ТРЕТІЙ жанр повідомлення — список причин, з якими людина
# лишається у формі після 422.
#
# ⚠️ Найважливіше твердження тут — дзеркальне до сусіднього `FlashMessages`, і
# саме тому їх легко переплутати. Там доводиться, що регіони стоять у DOM
# ЗАВЖДИ (порожня коробка мусить пережити morph, інакше AT не помітить зміни
# всередині). Тут — навпаки: порожній список не малює НІЧОГО, бо відповідь на
# 422 є повним рендером сторінки, вузол приходить новим разом зі своїм текстом,
# і `role="alert"` AT озвучує саме в цьому випадку. Порожня рамка тут не додала
# б чутності — лише рамку на кожній чистій формі.
RSpec.describe Views::Shared::UI::ErrorSummary do
  describe "коли причин немає" do
    it "не рендерить нічого на порожньому списку" do
      expect(render_component(messages: [])).to eq("")
    end

    it "не рендерить нічого на nil" do
      expect(render_component(messages: nil)).to eq("")
    end

    # `full_messages` порожніх рядків не віддає, але викликач може передати
    # результат власного `map`, і рамка з порожнім `<li>` виглядала б як збій.
    it "не рендерить нічого, коли всі рядки порожні" do
      expect(render_component(messages: [ "", nil, "  " ])).to eq("")
    end
  end

  describe "коли причини є" do
    let(:html) { render_component(messages: [ "Name can't be blank", "Email is invalid" ]) }

    it "показує кожну причину" do
      expect(html).to include("Name can&#39;t be blank").and include("Email is invalid")
    end

    # 🔴 Роль несуча, а не декоративна: без неї блок з'являється НІМИМ для
    # скрінрідера — сторінка просто перемальовується, і незряча людина не має
    # жодного сигналу, що сабміт не пройшов.
    it "оголошує себе як alert" do
      expect(html).to include('role="alert"')
    end

    it "бере спільний заголовок, коли власного не передано" do
      expect(html).to include("Validation Failed")
    end

    it "тримає причини списком, а не суцільним рядком" do
      expect(html.scan("<li>").size).to eq(2)
    end
  end

  # 🔴 Заголовок — параметр саме тому, що три реалізації, які цей компонент
  # замінив, казали НЕ одне й те саме: провізія повідомляє про невдалу
  # ініціацію вузла (де більшість причин узагалі не з валідації моделі), а не
  # про «перевірку не пройдено».
  describe "коли заголовок передано" do
    let(:html) { render_component(messages: [ "UID already taken" ], title: "Initiation Failed:") }

    it "показує переданий заголовок" do
      expect(html).to include("Initiation Failed:")
    end

    it "не показує спільного" do
      expect(html).not_to include("Validation Failed")
    end
  end
end
