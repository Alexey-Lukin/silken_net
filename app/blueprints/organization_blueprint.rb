# frozen_string_literal: true

class OrganizationBlueprint < Blueprinter::Base
  identifier :id

  view :index do
    fields :name, :crypto_public_address, :created_at
    field(:total_clusters) { |org| org.total_clusters }
    field(:total_invested) { |org| org.total_invested }
  end

  view :show do
    fields :name, :crypto_public_address, :billing_email, :created_at
  end
end
