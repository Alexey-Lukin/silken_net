# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Stub ActiveStorage and route helpers that require real blobs/routes during rendering.
unless Views::Shared::UI::PhotoCard.method_defined?(:_test_route_helpers_stubbed)
  Views::Shared::UI::PhotoCard.prepend(Module.new do
    def _test_route_helpers_stubbed = true
    def rails_blob_path(*, **) = "/rails/blobs/mock"
    def rails_representation_path(*, **) = "/rails/representations/mock"
    def api_v1_maintenance_record_photo_path(*, **) = "/api/v1/maintenance_records/42/photos/1"
  end)
end

RSpec.describe Views::Shared::UI::PhotoCard do
  # Minimal mock for ActiveStorage::Blob interface
  let(:mock_photo) do
    OpenStruct.new(
      filename: ActiveStorage::Filename.new("forest_canopy.jpg"),
      byte_size: 2_048_576,
      representable?: true,
      variant: ->(_style) { "variant_thumb" }
    )
  end

  let(:mock_record) do
    OpenStruct.new(id: 42, to_model: OpenStruct.new(model_name: OpenStruct.new(route_key: "maintenance_records")))
  end

  # PhotoCard requires Rails route helpers and ActiveStorage URL helpers
  # that are not available in unit rendering via .call.
  # We test the component structure and properties via mock-safe assertions.

  describe "initialization" do
    it "accepts photo, record, and editable params" do
      component = component_class.new(photo: mock_photo, record: mock_record, editable: true)
      expect(component).to be_a(described_class)
    end

    it "defaults editable to false" do
      component = component_class.new(photo: mock_photo, record: mock_record)
      expect(component.instance_variable_get(:@editable)).to be false
    end

    it "stores the photo reference" do
      component = component_class.new(photo: mock_photo, record: mock_record)
      expect(component.instance_variable_get(:@photo)).to eq(mock_photo)
    end

    it "stores the record reference" do
      component = component_class.new(photo: mock_photo, record: mock_record)
      expect(component.instance_variable_get(:@record)).to eq(mock_record)
    end
  end

  describe "validation" do
    it "raises ArgumentError when photo does not respond to :filename" do
      expect { component_class.new(photo: "invalid", record: mock_record) }
        .to raise_error(ArgumentError, /photo must respond to :filename/)
    end

    it "accepts any object responding to :filename" do
      simple_photo = OpenStruct.new(filename: "test.jpg")
      expect { component_class.new(photo: simple_photo, record: mock_record) }
        .not_to raise_error
    end
  end

  describe "design system compliance (via private methods)" do
    let(:component) { component_class.new(photo: mock_photo, record: mock_record, editable: true) }

    it "uses design system surface token in card classes" do
      card_classes = component.send(:card_classes)
      expect(card_classes).to include("bg-gaia-surface")
    end

    it "uses design system border token in card classes" do
      card_classes = component.send(:card_classes)
      expect(card_classes).to include("border-gaia-border")
    end

    it "uses hover border primary in card classes" do
      card_classes = component.send(:card_classes)
      expect(card_classes).to include("hover:border-gaia-primary")
    end

    it "uses shadow-sm with dark:shadow-none" do
      card_classes = component.send(:card_classes)
      expect(card_classes).to include("shadow-sm")
      expect(card_classes).to include("dark:shadow-none")
    end

    it "uses focus-visible ring on preview links" do
      link_classes = component.send(:preview_link_classes)
      expect(link_classes).to include("focus-visible:ring-2")
      expect(link_classes).to include("focus-visible:ring-gaia-primary")
    end

    it "uses semantic status tokens for delete button" do
      delete_classes = component.send(:delete_button_classes)
      expect(delete_classes).to include("bg-status-danger")
      expect(delete_classes).to include("text-status-danger-text")
    end

    it "uses focus-visible ring on delete button" do
      delete_classes = component.send(:delete_button_classes)
      expect(delete_classes).to include("focus-visible:ring-2")
      expect(delete_classes).to include("focus-visible:ring-status-danger-accent")
    end
  end

  describe "with editable true" do
    let(:component) { component_class.new(photo: mock_photo, record: mock_record, editable: true) }

    it "stores editable flag as true" do
      expect(component.instance_variable_get(:@editable)).to be true
    end
  end

  describe "with editable false" do
    let(:component) { component_class.new(photo: mock_photo, record: mock_record, editable: false) }

    it "stores editable flag as false" do
      expect(component.instance_variable_get(:@editable)).to be false
    end
  end

  describe "typography" do
    let(:component) { component_class.new(photo: mock_photo, record: mock_record) }

    it "uses text-mini for file fallback filename" do
      source = component.method(:render_file_fallback).source_location.first
      content = File.read(source)
      expect(content).to include("text-mini")
    end

    it "uses text-micro for metadata overlay" do
      source = component.method(:render_meta_overlay).source_location.first
      content = File.read(source)
      expect(content).to include("text-micro")
    end
  end

  # ---------------------------------------------------------------------------
  # Full rendering via ApplicationController.renderer
  # ---------------------------------------------------------------------------
  describe "rendered output" do
    let(:renderable_photo) do
      p = OpenStruct.new(
        filename: ActiveStorage::Filename.new("forest_canopy.jpg"),
        byte_size: 2_048_576,
        representable?: true
      )
      p.define_singleton_method(:variant) { |_style| "variant_thumb" }
      p
    end

    def render_card(**overrides)
      opts = { photo: renderable_photo, record: mock_record, editable: false }.merge(overrides)
      ApplicationController.renderer.render(
        component_class.new(**opts),
        layout: false
      )
    end

    context "with representable photo" do
      it "renders an img tag for representable photos" do
        html = render_card
        expect(html).to include("<img")
        expect(html).to include("forest_canopy.jpg")
      end

      it "renders the meta overlay with filename and size" do
        html = render_card
        expect(html).to include("forest_canopy.jpg")
        expect(html).to include("MB")
      end

      it "wraps content in the card container" do
        html = render_card
        expect(html).to include("bg-gaia-surface")
        expect(html).to include("border-gaia-border")
      end
    end

    context "with non-representable photo" do
      let(:non_representable_photo) do
        OpenStruct.new(
          filename: ActiveStorage::Filename.new("data_export.csv"),
          byte_size: 512_000,
          representable?: false
        )
      end

      it "renders the file fallback with paperclip icon" do
        html = render_card(photo: non_representable_photo)
        expect(html).to include("📎")
      end

      it "renders the filename in the fallback" do
        html = render_card(photo: non_representable_photo)
        expect(html).to include("data_export.csv")
      end

      it "renders the human-readable file size in the fallback" do
        html = render_card(photo: non_representable_photo)
        expect(html).to include("500 KB")
      end
    end

    context "with editable true" do
      it "renders the delete button" do
        html = render_card(editable: true)
        expect(html).to include("×")
        expect(html).to include(I18n.t("ui.photo_card.remove_photo", filename: mock_photo.filename))
      end
    end

    context "with editable false" do
      it "does not render the delete button" do
        html = render_card(editable: false)
        expect(html).not_to include(I18n.t("ui.photo_card.remove_photo", filename: mock_photo.filename))
      end
    end
  end
end
