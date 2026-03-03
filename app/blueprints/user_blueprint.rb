# frozen_string_literal: true

class UserBlueprint < Blueprinter::Base
  identifier :id

  # Публічний профіль (використовується в GET /api/v1/users/me)
  view :profile do
    fields :email_address, :first_name, :last_name, :role, :last_seen_at
    field(:full_name) { |user| user.full_name }
  end

  # Список екіпажу (використовується в GET /api/v1/users)
  view :crew do
    fields :first_name, :last_name, :role, :last_seen_at
    field(:full_name) { |user| user.full_name }
  end
end
