# frozen_string_literal: true

# [FW.54/SEC.3] Кремнієвий паспорт дерева: 96-біт STM32 UID (24 hex, три
# %08X-слова у порядку регістрів 0x1FFF7590/94/98). Дозволяє відрізнити
# re-flash того самого чипа від birthday-колізії 32-біт DID двох різних
# чипів (03_01 §7: колізія → quarantine юніта). NULL = legacy-дерево,
# створене до one-pass провіженінгу.
class AddSiliconUidHexToTrees < ActiveRecord::Migration[8.1]
  def change
    add_column :trees, :silicon_uid_hex, :string
    # Pre-launch: trees — dev-обсяг (одиниці рядків), non-concurrent lock
    # нешкідливий; safety_assured документує свідомий вибір (патерн ARCH.52).
    safety_assured do
      add_index :trees, :silicon_uid_hex, unique: true, where: "silicon_uid_hex IS NOT NULL"
    end
  end
end
