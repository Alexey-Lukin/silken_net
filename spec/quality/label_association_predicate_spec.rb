# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [UI.3] GREEN-половина предиката `LabelAssociation` (§Guard-craft #52).
#
# 🔴 Чому окремий файл, а не ще один приклад у компонентній спеці: пін над реальним
# компонентом доводить лише RED-бік («ця розмітка звʼязана»), і поки в дереві немає
# законної ВКЛАДЕНОЇ мітки, over-broad предикат виглядає здоровим. Тобто відсутню
# половину неможливо додати там, де живуть його споживачі — потрібен корпус форм,
# якого в застосунку сьогодні нема.
#
# ⚠️ Це НЕ дублювання логіки (§Guard-craft #12): очікування тут — незалежні
# ЛІТЕРАЛИ (порожньо / рівно ця мітка), а не повтор обчислення предиката.
RSpec.describe LabelAssociation do
  def fragment(html) = Nokogiri::HTML5.fragment(html)

  describe ".orphan_labels — GREEN на законних формах" do
    it "приймає ЯВНУ асоціацію (`for` ⟷ `id`)" do
      doc = fragment(%(<label for="email">Email</label><input id="email" type="text">))

      expect(described_class.orphan_labels(doc)).to be_empty
    end

    # 🔴 Форма, якої в дереві сьогодні НУЛЬ — і саме тому вона тут. Перша ж
    # правильно написана вкладена мітка червонила б пін, а найдешевша реакція
    # на червоний гейт при чесному коді — послабити гейт.
    it "приймає НЕЯВНУ асоціацію (мітка обгортає контрол), хоч живих сайтів нема" do
      doc = fragment(%(<label>Email<input type="text"></label>))

      expect(described_class.orphan_labels(doc)).to be_empty
    end

    it "приймає вкладений `select` так само, як `input`" do
      doc = fragment(%(<label>Мова<select><option>uk</option></select></label>))

      expect(described_class.orphan_labels(doc)).to be_empty
    end
  end

  describe ".orphan_labels — RED там, де звʼязку справді немає" do
    it "ловить мітку-сиблінга без `for`" do
      doc = fragment(%(<div><label>Email</label><input id="email" type="text"></div>))

      expect(described_class.orphan_labels(doc).map(&:text)).to eq([ "Email" ])
    end

    # Найтихіша форма: атрибут Є, тобто розмітка виглядає доглянутою, а ціль
    # не існує — друкарська помилка в `id` не має жодного симптому на екрані.
    it "ловить `for`, що показує в нікуди" do
      doc = fragment(%(<label for="emial">Email</label><input id="email" type="text">))

      expect(described_class.orphan_labels(doc).map(&:text)).to eq([ "Email" ])
    end
  end

  describe ".dangling_descriptions" do
    it "мовчить, коли `aria-describedby` резолвиться" do
      doc = fragment(%(<input aria-describedby="hint"><p id="hint">Формат: +380…</p>))

      expect(described_class.dangling_descriptions(doc)).to be_empty
    end

    it "ловить підказку, на яку показують, але якої немає" do
      doc = fragment(%(<input aria-describedby="hint">))

      expect(described_class.dangling_descriptions(doc)).to eq([ "hint" ])
    end
  end
end
