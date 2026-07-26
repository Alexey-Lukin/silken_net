# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Views::Shared::UI::DataTable do
  let(:columns) do
    [
      { label: "Name", class: "w-1/3" },
      { label: "Status" },
      { label: "Value", class: "text-right" }
    ]
  end

  def render_component(**kwargs, &block)
    component_class.new(**kwargs, &block).call
  end

  describe "with columns and rows" do
    # Pass a block so the rows path (tbody with divide styling) is exercised.
    let(:html) do
      component_class.new(columns: columns).call { "row content" }
    end

    it "renders a table element" do
      expect(html).to include("<table")
    end

    it "renders column headers" do
      expect(html).to include("Name")
      expect(html).to include("Status")
      expect(html).to include("Value")
    end

    it "renders thead with column scope" do
      expect(html).to include('scope="col"')
    end

    it "renders tbody with divide styling" do
      expect(html).to include("divide-y")
      expect(html).to include("divide-gaia-border")
    end

    it "applies per-column CSS classes" do
      expect(html).to include("w-1/3")
      expect(html).to include("text-right")
    end
  end

  describe "with empty: true (no rows)" do
    let(:html) { render_component(columns: columns, empty: true) }

    it "renders the table structure" do
      expect(html).to include("<table")
      expect(html).to include("<thead")
      expect(html).to include("<tbody")
    end

    it "renders the default i18n empty message" do
      I18n.with_locale(:en) do
        expect(render_component(columns: columns, empty: true)).to include(I18n.t("ui.data_table.empty"))
      end
    end
  end

  describe "with custom empty_message" do
    it "renders the custom empty message when empty: true" do
      html = render_component(columns: columns, empty_message: "Nothing here.", empty: true)
      expect(html).to include("Nothing here.")
      expect(html).to include("<td")
    end

    it "renders the default i18n empty message when empty: true with no custom message" do
      I18n.with_locale(:en) do
        html = render_component(columns: columns, empty: true)
        expect(html).to include(I18n.t("ui.data_table.empty"))
      end
    end

    it "spans all columns in the empty row" do
      html = render_component(columns: columns, empty_message: "Nope.", empty: true)
      expect(html).to include("colspan=\"#{columns.size}\"")
    end
  end

  describe "design system compliance" do
    let(:html) { render_component(columns: columns) }

    it "uses design system surface token for background" do
      expect(html).to include("bg-gaia-surface")
    end

    it "uses design system border token" do
      expect(html).to include("border-gaia-border")
    end

    it "uses shadow-sm for light mode depth" do
      expect(html).to include("shadow-sm")
    end

    it "disables shadow in dark mode" do
      expect(html).to include("dark:shadow-none")
    end

    it "uses bg-gaia-surface-sunken for thead" do
      expect(html).to include("bg-gaia-surface-sunken")
    end

    it "uses text-gaia-text-muted for thead" do
      expect(html).to include("text-gaia-text-muted")
    end

    it "uses font-mono for table text" do
      expect(html).to include("font-mono")
    end

    it "uses text-compact for table typography" do
      expect(html).to include("text-compact")
    end

    it "uses text-mini for header typography" do
      expect(html).to include("text-mini")
    end
  end

  describe "accessibility" do
    let(:html) { render_component(columns: columns) }

    it "includes role=table on the table element" do
      expect(html).to include('role="table"')
    end

    it "uses scope=col for header cells" do
      expect(html).to include('scope="col"')
    end
  end

  describe "with class override" do
    let(:html) { render_component(columns: columns, class: "mt-4") }

    it "accepts additional CSS classes" do
      expect(html).to include("mt-4")
    end
  end

  describe "with single column" do
    let(:html) { render_component(columns: [ { label: "ID" } ]) }

    it "renders a single column header" do
      expect(html).to include("ID")
    end
  end
end
