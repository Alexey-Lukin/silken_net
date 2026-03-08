# frozen_string_literal: true

# Model Drift Tracking для TinyMlModel (Zone 5.14: Галюцинації Оракула)
#
# ПРОБЛЕМА: Відсутні метрики поведінки моделі в полі.
# Ми не знаємо true_positive_rate / false_positive_rate
# для конкретної версії моделі.
#
# РІШЕННЯ: Додаємо статистичні поля для зворотного зв'язку (Feedback Loop).
# Дані оновлюються періодично з аналізу підтверджених/спростованих алертів.
class AddDriftTrackingToTinyMlModels < ActiveRecord::Migration[8.1]
  def change
    add_column :tiny_ml_models, :true_positive_rate, :decimal, precision: 5, scale: 4
    add_column :tiny_ml_models, :false_positive_rate, :decimal, precision: 5, scale: 4
    add_column :tiny_ml_models, :total_predictions, :integer, default: 0, null: false
    add_column :tiny_ml_models, :confirmed_predictions, :integer, default: 0, null: false
    add_column :tiny_ml_models, :drift_checked_at, :datetime
  end
end
