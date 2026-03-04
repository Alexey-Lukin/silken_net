# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organization, type: :model do
  describe "associations" do
    it "has gateways through clusters" do
      organization = create(:organization)
      cluster = create(:cluster, organization: organization)
      gateway = create(:gateway, cluster: cluster)

      expect(organization.gateways).to include(gateway)
    end
  end
end
