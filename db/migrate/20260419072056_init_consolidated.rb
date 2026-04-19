class InitConsolidated < ActiveRecord::Migration[8.1]
  def up
    # Schema loaded from db/structure.sql
    # This is a consolidated migration replacing all previous migrations.
    # To set up the database: bin/rails db:schema:load (preferred for new installs)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
