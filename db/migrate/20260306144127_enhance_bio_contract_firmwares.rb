class EnhanceBioContractFirmwares < ActiveRecord::Migration[8.1]
  def change
    change_table :bio_contract_firmwares do |t|
      # 1. SHA-256 Integrity: хеш бінарного вмісту для перевірки цілісності
      t.string :binary_sha256

      # 2. Species Specificity: тип обладнання (Tree/Gateway) та порода
      t.string :target_hardware_type
      t.references :tree_family, foreign_key: true, null: true

      # 4. Phased Rollout: відсоток пристроїв для поступового розгортання
      t.integer :rollout_percentage, default: 0
    end
  end
end
