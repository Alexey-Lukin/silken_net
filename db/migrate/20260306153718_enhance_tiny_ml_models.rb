class EnhanceTinyMlModels < ActiveRecord::Migration[8.1]
  def change
    change_table :tiny_ml_models do |t|
      # 1. Compatibility Gap: мінімальна версія прошивки для коректної роботи моделі
      t.string :min_firmware_version

      # 2. Weights Layout: формат ваг моделі (tflite, edge_impulse, onnx, c_array)
      t.string :model_format

      # 3. Phased Diffusion: відсоток пристроїв для поступового розгортання
      t.integer :rollout_percentage, default: 0
    end
  end
end
