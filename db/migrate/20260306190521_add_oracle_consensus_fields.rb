class AddOracleConsensusFields < ActiveRecord::Migration[8.1]
  def change
    # Ідентифікатор AI-моделі/Оракула, який згенерував інсайт
    add_column :ai_insights, :model_source, :string

    # Замінюємо старий унікальний індекс на новий, що включає model_source
    remove_index :ai_insights, name: :idx_ai_insights_unique_report
    add_index :ai_insights, [:analyzable_type, :analyzable_id, :target_date, :insight_type, :model_source],
              unique: true, name: :idx_ai_insights_unique_report

    # Кількість незалежних підтверджень для тригера страхування
    add_column :parametric_insurances, :required_confirmations, :integer, default: 3, null: false
  end
end
