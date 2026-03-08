# frozen_string_literal: true

# Evidence Persistence для AiInsight (Zone 5.13: Галюцинації Оракула)
#
# ПРОБЛЕМА: Інсайт без доказів — коли ШІ каже «це пожежа»,
# він не посилається на конкретні батчі телеметрії.
#
# РІШЕННЯ: source_log_ids — масив ID телеметрії, щоб оператор
# міг перевірити «чому ШІ так вирішив».
class AddSourceLogIdsToAiInsights < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_insights, :source_log_ids, :bigint, array: true, default: []
    add_index :ai_insights, :source_log_ids, using: :gin, name: "index_ai_insights_on_source_log_ids"
  end
end
