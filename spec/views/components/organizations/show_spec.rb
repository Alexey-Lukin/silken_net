# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::Show do
  def mock_cluster(id: 1, name: "Carpathian-Alpha", health_index: 0.85, total_active_trees: 24)
    c = OpenStruct.new(
      id: id,
      name: name,
      health_index: health_index,
      total_active_trees: total_active_trees
    )
    c.define_singleton_method(:model_name) { ActiveModel::Name.new(Cluster) }
    c.define_singleton_method(:to_key) { [ id ] }
    c.define_singleton_method(:to_param) { id.to_s }
    c
  end

  def mock_org(name: "Cherkasy Forest Fund", created_at: 2.years.ago,
               crypto_public_address: "0xABCD1234", billing_email: "billing@forest.org",
               total_contracted: "50000")
    OpenStruct.new(
      name: name,
      created_at: created_at,
      crypto_public_address: crypto_public_address,
      billing_email: billing_email,
      total_contracted: total_contracted
    )
  end

  def render_component(organization:, clusters:, performance:)
    ApplicationController.renderer.render(
      component_class.new(organization: organization, clusters: clusters, performance: performance),
      layout: false
    )
  end

  let(:org) { mock_org }
  let(:clusters) { [ mock_cluster ] }
  let(:performance) { { total_trees: 42, carbon_minted: "1234 SCC" } }
  let(:html) { render_component(organization: org, clusters: clusters, performance: performance) }

  describe "org name display" do
    it "renders the organization name" do
      expect(html).to include("Cherkasy Forest Fund")
    end

    it "renders Member Since with creation date" do
      expect(html).to include("Member Since:")
    end
  end

  describe "FULLY_SYNCED status" do
    it "renders FULLY_SYNCED operational status" do
      expect(html).to include("FULLY_SYNCED")
    end

    it "renders Operational Status label" do
      expect(html).to include("Operational Status")
    end
  end

  describe "StatCards for 3 metrics" do
    it "renders Monitored Trees stat card" do
      expect(html).to include("Monitored Trees")
    end

    it "renders Soldier Trees sub-label" do
      expect(html).to include("Soldier Trees")
    end

    it "renders SCC Minted stat card" do
      expect(html).to include("SCC Minted")
    end

    it "renders Carbon minted value" do
      expect(html).to include("1234 SCC")
    end

    it "renders Contracted Amount stat card" do
      expect(html).to include("Contracted Amount")
    end

    it "renders total_trees count" do
      expect(html).to include("42")
    end
  end

  describe "cluster table" do
    it "renders Assigned Sectors heading" do
      expect(html).to include("Assigned Sectors")
    end

    it "renders the cluster name" do
      expect(html).to include("Carpathian-Alpha")
    end

    it "renders the active soldiers count" do
      expect(html).to include("24 Soldiers")
    end

    it "renders the health index as percentage" do
      expect(html).to include("85%")
    end

    it "renders the Open Matrix link" do
      expect(html).to include("Open Matrix →")
    end
  end

  describe "identity vault" do
    it "renders On-Chain Identity Vault heading" do
      expect(html).to include("On-Chain Identity Vault")
    end

    it "renders the crypto public address" do
      expect(html).to include("0xABCD1234")
    end

    it "renders billing contact" do
      expect(html).to include("billing@forest.org")
    end
  end

  describe "with multiple clusters" do
    it "renders all clusters" do
      clusters = [
        mock_cluster(id: 1, name: "Alpha"),
        mock_cluster(id: 2, name: "Beta")
      ]
      html = render_component(organization: org, clusters: clusters, performance: performance)
      expect(html).to include("Alpha")
      expect(html).to include("Beta")
    end
  end
end
