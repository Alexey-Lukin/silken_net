# frozen_string_literal: true

# @label Pagination
class PaginationPreview < Lookbook::Preview
  # @label Middle Page
  # @notes Shows pagination with previous and next links visible.
  def middle_page
    pagy = OpenStruct.new(page: 3, last: 10, prev: 2, next: 4)
    render Views::Shared::UI::Pagination.new(pagy: pagy, url_helper: ->(page:) { "#page=#{page}" })
  end

  # @label First Page
  # @notes First page — no previous link.
  def first_page
    pagy = OpenStruct.new(page: 1, last: 5, prev: nil, next: 2)
    render Views::Shared::UI::Pagination.new(pagy: pagy, url_helper: ->(page:) { "#page=#{page}" })
  end

  # @label Last Page
  # @notes Last page — no next link.
  def last_page
    pagy = OpenStruct.new(page: 5, last: 5, prev: 4, next: nil)
    render Views::Shared::UI::Pagination.new(pagy: pagy, url_helper: ->(page:) { "#page=#{page}" })
  end
end
