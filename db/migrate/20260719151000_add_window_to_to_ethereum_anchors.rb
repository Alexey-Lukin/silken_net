# frozen_string_literal: true

# [ARCH.12 Фаза 1а] Верхня межа вікна телеметрія-листя мусить бути ПЕРСИСТОВАНА,
# а не похідна anchored_at − GRACE: зміна GRACE-константи зсунула б історичні
# вікна і зламала б відтворюваність кореня. Пара (window_from, window_to)
# робить вікно самодостатнім назавжди.
class AddWindowToToEthereumAnchors < ActiveRecord::Migration[8.1]
  def change
    add_column :ethereum_anchors, :window_to, :timestamp
  end
end
