# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [UI.1] SilkenNet::Brand — Ruby-дзеркало @theme для поверхонь без CSS
# (Prawn-PDF, PWA-manifest). Дзеркало без свідка гниє мовчки (клас
# «гейт, що звіряє два НАШІ доми» тут НЕ діє: CSS-шафа — зовнішній якір
# для Ruby-константи, бо її значення бере браузер, а не наш код).
#
# Стеля: гейт звіряє ЗНАЧЕННЯ двох названих токенів; він не знає, хто ще
# в дереві носить бренд-hex літералом (те стереже gaia:lint_tokens у
# view-шарі та ручний греп поза ним — 00_07 UI.1).
RSpec.describe SilkenNet::Brand do
  let(:css) { Rails.root.join("app/assets/tailwind/application.css").read }
  let(:dark_start) { css.index(/^@media screen and \(prefers-color-scheme: dark\) \{/) }

  def token(fragment, name)
    fragment[/#{Regexp.escape(name)}:\s*([^;]+);/, 1]&.strip
  end

  it "читає обидві шафи (ліхтар: межа dark-блоку знайдена)" do
    expect(dark_start).to be_present
  end

  it "PRIMARY_HEX дзеркалить --gaia-primary (light-шафа; у dark воно byte-те саме)" do
    expect(token(css[0...dark_start], "--gaia-primary"))
      .to eq(described_class::PRIMARY_HEX)
  end

  it "PRIMARY_PRAWN — та сама величина без ґратки (Prawn-форма)" do
    expect("##{described_class::PRIMARY_PRAWN}").to eq(described_class::PRIMARY_HEX)
  end

  it "SURFACE_BASE_DARK_HEX дзеркалить --gaia-surface-base ТЕМНОЇ шафи" do
    expect(token(css[dark_start..], "--gaia-surface-base"))
      .to eq(described_class::SURFACE_BASE_DARK_HEX)
  end

  # Іконка — статична поверхня поза CSS І поза Ruby-рендером (favicon · apple-touch · PWA-manifest),
  # тож бренд там стоїть ЛІТЕРАЛОМ, а PNG ще й розтровий. Стеля: SVG судиться по атрибутах кольору,
  # PNG — по розміру й двох пікселях (тло та ядро гліфа); ФОРМИ гліфа і безпечного кола `maskable`
  # не бачить жоден із прикладів.
  it "icon.svg малює рівно двома бренд-кольорами" do
    svg = Rails.public_path.join("icon.svg").read
    colours = svg.scan(/(?:fill|stroke)="(#\h{6})"/).flatten.map(&:downcase).uniq

    expect(colours).to contain_exactly(described_class::PRIMARY_HEX, described_class::SURFACE_BASE_DARK_HEX)
  end

  it "icon.png — растр того самого гліфа, у розмірі, який оголошує manifest" do
    require "vips"
    png = Vips::Image.new_from_file(Rails.public_path.join("icon.png").to_s)
    pixel = ->(x, y) { format("#%02x%02x%02x", *png.getpoint(x, y).first(3).map(&:round)) }
    declared = Rails.root.join("app/views/pwa/manifest.json.erb").read.scan(/"sizes":\s*"(\d+)x(\d+)"/).uniq

    expect(declared).to eq([ [ png.width.to_s, png.height.to_s ] ])
    expect(png.has_alpha?).to be(false), "маскована ОС іконка мусить бути непрозорою до країв"
    expect(pixel.call(3, 3)).to eq(described_class::SURFACE_BASE_DARK_HEX)
    expect(pixel.call(png.width / 2, png.height / 2)).to eq(described_class::PRIMARY_HEX)
  end
end
