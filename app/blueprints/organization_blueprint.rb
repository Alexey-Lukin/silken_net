# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class OrganizationBlueprint < Blueprinter::Base
  identifier :id

  view :index do
    fields :name, :crypto_public_address, :created_at
    field(:total_clusters) { |org| org.total_clusters }
    field(:total_contracted) { |org| org.total_contracted }
  end

  view :show do
    fields :name, :crypto_public_address, :billing_email, :data_region, :created_at
  end
end
