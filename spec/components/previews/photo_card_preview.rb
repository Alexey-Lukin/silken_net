# frozen_string_literal: true

# @label Photo Card
# @display bg_color "#000"
# @notes PhotoCard requires ActiveStorage blobs and cannot be fully rendered in Lookbook
#   without a database connection. These previews demonstrate the component structure
#   using mock objects. For full interactive testing, use the MaintenanceRecord show page.
class PhotoCardPreview < Lookbook::Preview
  # @label Image Photo (Mock)
  # @notes Demonstrates the photo card layout with a representable image blob mock.
  def image_photo
    render_with_template(template: "photo_card_preview/mock_layout")
  end

  # @label File Fallback (Mock)
  # @notes Demonstrates the file fallback display when the blob is not representable.
  def file_fallback
    render_with_template(template: "photo_card_preview/file_fallback")
  end
end
