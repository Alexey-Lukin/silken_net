# frozen_string_literal: true

require "rails_helper"

RSpec.describe Provisioning::Success do
  def mock_cluster(id: 10, name: "Carpathian-Alpha")
    cluster = OpenStruct.new(id: id, name: name)
    cluster.define_singleton_method(:model_name) { ActiveModel::Name.new(Cluster) }
    cluster.define_singleton_method(:to_key) { [ id ] }
    cluster.define_singleton_method(:to_param) { id.to_s }
    cluster
  end

  def mock_device(did: "SNET-A1B2C3D4", uid: "00E4BF12", cluster: nil)
    OpenStruct.new(
      did: did,
      uid: uid,
      cluster: cluster || mock_cluster
    )
  end

  let(:device) { mock_device }

  describe "success indicator" do
    it "renders Ritual Complete heading" do
      html = render_component(device: device, aes_key: nil)
      expect(html).to include("Ritual Complete")
    end

    it "renders checkmark icon" do
      html = render_component(device: device, aes_key: nil)
      expect(html).to include("✓")
    end

    it "renders woven into Silken Net message" do
      html = render_component(device: device, aes_key: nil)
      expect(html).to include("Silken Net")
    end
  end

  describe "device data" do
    it "renders assigned DID" do
      html = render_component(device: device, aes_key: nil)
      expect(html).to include("SNET-A1B2C3D4")
    end

    it "renders hardware UID" do
      html = render_component(device: device, aes_key: nil)
      expect(html).to include("00E4BF12")
    end
  end

  describe "lab mode (legacy aes_key kwarg)" do
    # [SEC.11] aes_key kwarg is still accepted for backwards-spec-compat
    # but the component no longer renders it — there is no lab mode.
    let(:aes_key) { "AABBCCDDEEFF00112233445566778899AABBCCDDEEFF00112233445566778899" }
    let(:html)    { render_component(device: device, aes_key: aes_key) }

    it "does not render an AES-256 SESSION KEY notice" do
      expect(html).not_to include("AES-256 SESSION KEY")
    end

    it "does not leak the AES key into the rendered HTML" do
      expect(html).not_to include(aes_key)
    end

    it "renders the HKDF mode notice instead" do
      expect(html).to include("HKDF MODE")
    end
  end

  describe "HKDF production mode (no AES key)" do
    let(:html) { render_component(device: device, aes_key: nil) }

    it "renders HKDF MODE notice" do
      expect(html).to include("HKDF MODE")
    end

    it "renders HKDF-SHA256 reference" do
      expect(html).to include("HKDF-SHA256")
    end

    it "renders PROVISIONING_MASTER_KEY mention" do
      expect(html).to include("PROVISIONING_MASTER_KEY")
    end
  end

  describe "cluster link" do
    it "renders link to cluster" do
      html = render_component(device: device, aes_key: nil)
      expect(html).to include("View Node in Matrix")
    end

    it "links to the correct cluster path" do
      html = render_component(device: device, aes_key: nil)
      expect(html).to include("/api/v1/clusters/10")
    end
  end
end
