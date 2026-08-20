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
end
