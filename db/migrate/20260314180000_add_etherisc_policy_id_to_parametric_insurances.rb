# frozen_string_literal: true

class AddEtheriscPolicyIdToParametricInsurances < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :parametric_insurances, :etherisc_policy_id, :string
    add_index :parametric_insurances, :etherisc_policy_id, algorithm: :concurrently
  end
end
