class Init < ActiveRecord::Migration[8.1]
  def up
    # Schema loaded from db/structure.sql
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
