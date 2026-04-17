# frozen_string_literal: true

require "rails_helper"

RSpec.describe Provisioning::New do
  let(:component_class) { described_class }

  def render_component(**kwargs)
    ApplicationController.renderer.render(component_class.new(**kwargs), layout: false)
  end

  def mock_cluster(id: 1, name: "Carpathian-Alpha")
    cluster = OpenStruct.new(id: id, name: name)
    cluster.define_singleton_method(:model_name) { ActiveModel::Name.new(Cluster) }
    cluster.define_singleton_method(:to_key) { [id] }
    cluster.define_singleton_method(:to_param) { id.to_s }
    cluster
  end

  def mock_family(id: 1, name: "Oak")
    family = OpenStruct.new(id: id, name: name)
    family.define_singleton_method(:model_name) { ActiveModel::Name.new(TreeFamily) }
    family.define_singleton_method(:to_key) { [id] }
    family.define_singleton_method(:to_param) { id.to_s }
    family
  end

  def mock_device_with_errors(messages: ["Hardware UID can't be blank"])
    errors = double("errors", any?: true, full_messages: messages)
    OpenStruct.new(errors: errors)
  end

  let(:clusters) { [mock_cluster] }
  let(:families) { [mock_family] }
  let(:html)     { render_component(clusters: clusters, families: families) }

  describe "header section" do
    it "renders Hardware Initiation heading" do
      expect(html).to include("Hardware Initiation")
    end

    it "renders biometric link subtitle" do
      expect(html).to include("biometric link")
    end
  end

  describe "form fields" do
    it "renders hardware_uid field" do
      expect(html).to include("hardware_uid")
    end

    it "renders Physical Crystal ID label" do
      expect(html).to include("Physical Crystal ID")
    end

    it "renders device_type select with Soldier option" do
      expect(html).to include("Soldier")
    end

    it "renders device_type select with Queen option" do
      expect(html).to include("Queen")
    end

    it "renders cluster selection" do
      expect(html).to include("Carpathian-Alpha")
    end

    it "renders family selection" do
      expect(html).to include("Oak")
    end

    it "renders latitude field" do
      expect(html).to include("latitude")
    end

    it "renders longitude field" do
      expect(html).to include("longitude")
    end
  end

  describe "submit button" do
    it "renders BIND HARDWARE TO MATRIX button" do
      expect(html).to include("BIND HARDWARE TO MATRIX")
    end
  end

  describe "error display" do
    it "renders validation errors when device has errors" do
      device = mock_device_with_errors
      html = render_component(clusters: clusters, families: families, device: device)
      expect(html).to include("Initiation Failed")
      expect(html).to include("Hardware UID can")
    end

    it "does not render error section when device is nil" do
      expect(html).not_to include("Initiation Failed")
    end
  end
end
