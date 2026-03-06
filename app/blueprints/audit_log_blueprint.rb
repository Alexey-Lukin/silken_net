# frozen_string_literal: true

class AuditLogBlueprint < Blueprinter::Base
  identifier :id

  view :index do
    fields :action, :auditable_type, :auditable_id, :metadata, :created_at
    association :user, blueprint: UserBlueprint, view: :crew
  end

  view :show do
    fields :action, :auditable_type, :auditable_id, :metadata,
           :ip_address, :user_agent, :created_at
    association :user, blueprint: UserBlueprint, view: :profile
  end
end
