# frozen_string_literal: true

class AddIndexesAndFraudDetectedToAiInsights < ActiveRecord::Migration[8.1]
  def change
    # --- 1. Витягуємо fraud_detected з JSONB reasoning в окрему boolean колонку ---
    # Причина: store_accessor повертає строку з JSONB, що створює баг ("false" is truthy).
    # Окрема колонка дає правильну типізацію та швидкий пошук без GIN-індексу.
    add_column :ai_insights, :fraud_detected, :boolean, default: false, null: false

    # --- 2. Unique Composite Index (замість Rails-level uniqueness validation) ---
    # Причина: validates uniqueness робить SELECT перед INSERT — race condition при конкурентних воркерах.
    # DB-level unique index гарантує атомарність та відсікає дублікати на рівні заліза.
    add_index :ai_insights,
              [ :analyzable_type, :analyzable_id, :target_date, :insight_type ],
              unique: true,
              name: "idx_ai_insights_unique_report"

    # --- 3. GIN-індекс для JSONB reasoning (The Reasoning Filter) ---
    # Причина: Пошук по JSONB без GIN-індексу = full table scan на мільйонах записів.
    add_index :ai_insights, :reasoning, using: :gin, name: "idx_ai_insights_reasoning_gin"

    # --- 4. Індекс на target_date для скоупів for_date та upcoming ---
    add_index :ai_insights, :target_date, name: "idx_ai_insights_target_date"
  end
end
