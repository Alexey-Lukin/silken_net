# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# ⚖️ [SEC.18, 2026-08-20] EXIF-присуд має ДВІ половини, і кожна пінить свою:
# показ (variant :thumb) — БЕЗ метаданих (GPS+timestamp техніка = PII повз
# оголошені колонки, DSAR/anonymization їх не бачать), а ОРИГІНАЛ їх ТРИМАЄ —
# EXIF-геотег є потенційним незалежним доказом «технік був на місці»
# (Anti-Sofa-Repair, ⚖️ UI.7), і глобальний стрип знищив би його незворотно.
# Без другого прикладу перший, хто допише post-upload стрип оригіналу «для
# чистоти», лишив би сюїту зеленою — а присуд каже протилежне.
#
# Фікстура будує JPEG із GPS-EXIF самим vips (той самий тракт, що й
# image_processing), і несе ЛІХТАР: доводить присутність метаданих ДО
# перевірки — інакше «variant чистий» було б зелене й на кадрі, який
# метаданих ніколи не мав (вакуум за побудовою).
RSpec.describe MaintenanceRecord do
  def jpeg_with_gps
    require "vips"
    img = Vips::Image.black(64, 64, bands: 3).copy(interpretation: :srgb)
    img = img.mutate do |m|
      m.set_type! GObject::GSTR_TYPE, "exif-ifd3-GPSLatitude", "49/1 26/1 40/1 (49.4444) [3 rationals]"
      m.set_type! GObject::GSTR_TYPE, "exif-ifd3-GPSLongitude", "32/1 3/1 35/1 (32.0597) [3 rationals]"
      m.set_type! GObject::GSTR_TYPE, "exif-ifd0-Make", "TestPhone (TestPhone) [ASCII]"
    end
    img.jpegsave_buffer
  end

  def exif_fields(bytes)
    Vips::Image.jpegload_buffer(bytes).get_fields.grep(/\Aexif-/)
  end

  let(:record) { create(:maintenance_record) }

  it "strips EXIF (incl. GPS) from the display variant while the ORIGINAL keeps it as evidence" do
    bytes = jpeg_with_gps

    # Ліхтар фікстури: без доведеного EXIF на вході обидві перевірки нижче вакуумні.
    source_fields = exif_fields(bytes)
    expect(source_fields).not_to be_empty
    expect(source_fields.join(" ")).to include("GPSLatitude")

    record.photos.attach(
      io: StringIO.new(bytes), filename: "probe.jpg", content_type: "image/jpeg"
    )
    photo = record.photos.first

    variant_bytes = photo.variant(:thumb).processed.download
    expect(exif_fields(variant_bytes)).to be_empty

    original_bytes = photo.download
    original_fields = exif_fields(original_bytes)
    expect(original_fields.join(" ")).to include("GPSLatitude")
  end
end
