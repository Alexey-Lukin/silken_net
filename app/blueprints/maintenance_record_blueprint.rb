# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class MaintenanceRecordBlueprint < Blueprinter::Base
  identifier :id

  view :index do
    fields :action_type, :performed_at, :notes,
           :labor_hours, :parts_cost,
           :hardware_verified,
           :latitude, :longitude

    # [ARCH.103] `&.` несучий: суперечність було видно в ОДНОМУ payload'і — обидва
    # доданки чесно віддавались як `null`, а похідний `total_cost` поруч друкував
    # упевнений `0.0`. Інтегратор не мав жодного способу відрізнити «візит нічого
    # не коштував» від «вартість не вводили».
    field(:total_cost) { |r| r.total_cost&.round(2) }
    field(:photo_count) { |r| r.photos.size }
    field(:maintainable_label) { |r| "#{r.maintainable_type} // #{r.maintainable&.display_identifier}" }

    association :user, blueprint: UserBlueprint, view: :minimal
  end

  view :show do
    include_view :index

    field(:photo_urls) do |r, options|
      r.photos.map do |photo|
        {
          id:        photo.id,
          thumb_url: options[:url_helpers]&.rails_representation_url(
                       photo.variant(:thumb), only_path: true
                     ) || "",
          full_url:  options[:url_helpers]&.rails_blob_url(photo, only_path: true) || "",
          filename:  photo.filename.to_s,
          byte_size: photo.byte_size
        }
      end
    end
  end
end
