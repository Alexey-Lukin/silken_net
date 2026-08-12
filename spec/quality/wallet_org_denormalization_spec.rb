# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [ARCH.87] Носій інваріанта, на який спирається `WalletPolicy::Scope`.
#
# `wallets.organization_id` — свідомий денормалізований ярлик (`Tree#build_default_wallet`
# пише його як `cluster&.organization` на момент народження дерева) з рівно ОДНИМ письменником
# і жодним бекфілом. Політика приймає його в `OR` разом із похідним ланцюгом
# `tree → cluster → organization`, і однозначність того `OR` тримається на тому, що дві
# сторони ніколи не розходяться.
#
# 🔴 Чому інваріант не декларативний, а структурний (⚖️ ратифіковано 2026-07-30): єдине, що
# могло б його зламати, — переїзд дерева в інший кластер, а такої операції НЕ ІСНУЄ й не може
# існувати. `clusters.id` — фабрично заморожена координата юніта: він HKDF-salt для
# `K_ota`/`KEYB`, прошитих у кремній і незмінних після RDP-lock. Канон робить «переїзд» парою
# «decommission старого юніта + factory-provision нового з новим DID».
#
# ⚠️ Стеля названа чесно: приклади нижче стережуть КОД, який міг би зламати інваріант
# (новий письменник колонки), і РОЗБІЖНІСТЬ у наборі, побудованому штатним шляхом. Вони НЕ
# бачать ручного `update_column` у консолі — таке лишається операторською відповідальністю.
RSpec.describe "wallets.organization_id denormalisation invariant", type: :model do
  describe "письменники колонки" do
    # Другий письменник — це і є спосіб зламати інваріант: він міг би поставити
    # значення, не узгоджене з `tree.cluster.organization_id`.
    # ⚠️ Прилад валідовано на ВІДОМОМУ сайті перш ніж покладатись на його мовчання:
    # перша редакція шукала `organization_id:` і давала НУЛЬ, бо письменник ставить
    # асоціацію (`create_wallet!(organization: …)`). Інструмент, що не знаходить
    # відомого, не знайшов би невідомого.
    #
    # 🔴 СТЕЛЯ, названа прямо (виміряна мутацією, не виведена): детектор ключується на
    # ІМЕНІ отримувача. `w.organization = nil`, де `w` — гаманець під довільною назвою,
    # він НЕ побачить, і закрити це статично неможливо — тип локальної змінної без
    # рантайму не визначається. Це та сама свідома сліпота, що в
    # `partition_key_discipline` до асоціацій. Гейт стереже ФОРМИ, якими писав би
    # притомний автор; решту тримає ревʼю.
    def self.writer_forms
      /create_wallet!?\([^)]*organization|[A-Za-z_]*wallet[A-Za-z_]*\.organization(_id)?\s*=|wallets?\.update(_all)?\([^)]*organization_id/i
    end

    # ⚠️ Прозу відсіюємо явно: перша редакція червоніла на КОМЕНТАРІ, що цитує форму
    # (перевірено мутацією). Гейт, який не відрізняє код від документації про себе,
    # переносить цю сліпоту в кожен ручний підрахунок після нього.
    # ⚠️ `where(...)` відсіюємо як ЧИТАННЯ: SQL-предикат `"wallets.organization_id = :org"`
    # синтаксично невідрізненний від присвоєння, і перша редакція червоніла на власному
    # ж скоупі політики — гейт, що ловить свій легітимний рядок, знімають першим.
    def self.write_line?(line)
      stripped = line.strip
      return false if stripped.start_with?("#")
      return false if stripped.match?(/\bwhere\(/)

      stripped.match?(writer_forms)
    end

    it "лишається рівно один, і це народження гаманця разом із деревом" do
      writers = Dir.glob("app/**/*.rb").select do |path|
        File.readlines(path).any? { |line| self.class.write_line?(line) }
      end

      expect(writers).to contain_exactly("app/models/tree.rb")
    end
  end

  describe "узгодженість колонки з ланцюгом" do
    let(:organization) { create(:organization) }
    let(:cluster) { create(:cluster, organization: organization) }

    it "гаманець народжується з організацією свого кластера" do
      tree = create(:tree, cluster: cluster)

      expect(tree.wallet.organization_id).to eq(organization.id)
      expect(tree.wallet.organization_id).to eq(tree.cluster.organization_id)
    end

    it "у штатно побудованому наборі колонка НІДЕ не розходиться з ланцюгом" do
      create_list(:tree, 3, cluster: cluster)
      create(:tree, cluster: create(:cluster, organization: create(:organization)))

      drift = Wallet.joins(tree: :cluster)
                    .where("wallets.organization_id IS DISTINCT FROM clusters.organization_id")

      expect(drift).to be_empty
    end

    # Дерево без кластера — СВІДОМО дозволений захисний стан (`belongs_to :cluster,
    # optional: true`; три спеки дерева навмисно його проганяють). Тоді колонка порожня,
    # і саме через це `Scope` мусить приймати ще й ланцюг — інакше такий гаманець
    # зникає зі списку, лишаючись відкритим за прямою адресою.
    it "порожня колонка НЕ вважається розбіжністю — це відсутність, не конфлікт" do
      tree = create(:tree, cluster: nil)

      expect(tree.wallet.organization_id).to be_nil
      expect(tree.cluster).to be_nil
    end
  end
end
