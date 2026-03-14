# frozen_string_literal: true

# @label Data Table
class DataTablePreview < Lookbook::Preview
  # @label Default
  # @notes Renders a data table with sample columns and rows.
  def default
    render_with_template(template: "data_table_preview/default")
  end

  # @label Empty State
  # @notes Shows the table with no rows, falling back to the empty message.
  def empty
    render_with_template(template: "data_table_preview/empty")
  end
end
