# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# Статичні сторінки помилок `public/*.html` — єдина поверхня UI, що несе бренд-кольори й
# людський текст ЛІТЕРАЛАМИ: Rails віддає їх повз asset-пайплайн, I18n і layout
# (`PublicExceptions` — для збою, що оминув усі `rescue_from`; `allow_browser` — для 406).
# Форма та сама, що в `SilkenNet::Brand` (`brand_spec.rb`): дзеркало без свідка гниє мовчки.
#
# Осі, кожна з власною ціною промаху:
#   · токени — значення кожної оголошеної змінної дорівнює значенню в ТІЙ САМІЙ темі
#     `application.css`, темна тема оголошує ту саму множину, що світла, і кожна вжита `var()`
#     оголошена (інакше зміна бренду лишає сторінки помилок у старому кольорі, забута пара дає
#     світле значення в темній темі, а неоголошена змінна малює прозорість без жодної помилки);
#   · локалі — словник покриває рівно `available_locales` мінус мову розмітки, і кожен запис
#     має всі ключі сторінки (інакше нова локаль мовчки дістає англійську);
#   · канон — там, де сторінка каже те саме, що `Errors::Page`, вона каже це СЛОВАМИ
#     `errors.api.*`, а не переказом.
#
# Стеля: вигляду гейт не бачить — контраст і верстку судить око, в обох темах.
RSpec.describe "public/*.html error pages mirror their homes" do # rubocop:disable RSpec/DescribeClass
  def self.theme_blocks
    css = Rails.root.join("app/assets/tailwind/application.css").read
    {
      light: css[/^:root \{.*?^\}/m],
      dark: css[/^@media screen and \(prefers-color-scheme: dark\) \{.*?^\}/m]
    }
  end

  def self.canon
    {
      "400.html" => { "heading" => "errors.api.bad_request_title", "message" => "errors.api.bad_request" },
      "404.html" => { "heading" => "errors.api.not_found_title" },
      "500.html" => { "heading" => "errors.api.internal_title", "message" => "errors.api.internal" }
    }
  end

  def self.pages = Rails.root.glob("public/*.html").sort

  def declarations(block)
    block.scan(/^\s*(--[\w-]+):\s*([^;]+);/).to_h { |token, value| [ token, value.strip ] }
  end

  it "бачить усі сторінки, які Rails шукає (ліхтар: порожній glob = нуль прикладів = хибний зелений)" do
    expect(self.class.pages.map { |p| p.basename.to_s })
      .to include("400.html", "404.html", "406-unsupported-browser.html", "422.html", "500.html")
    expect(self.class.theme_blocks.values).to all(be_present)
  end

  pages.each do |path|
    context path.basename.to_s do
      let(:name)  { path.basename.to_s }
      let(:html)  { path.read }
      let(:style) { html[%r{<style>(.*?)</style>}m, 1] }
      let(:doc)   { Nokogiri::HTML5(html) }
      let(:markup) { doc.css("[data-i18n]").to_h { |node| [ node["data-i18n"], node.text ] } }
      let(:translations) { JSON.parse(doc.at_css("script#translations").text) }
      let(:page_blocks) do
        {
          light: style[/:root \{.*?\}/m],
          dark: style[/@media screen and \(prefers-color-scheme: dark\) \{\s*:root \{.*?\}/m]
        }
      end

      it "кожен токен дорівнює своєму значенню в тій самій темі application.css" do
        expect(page_blocks.values).to all(be_present)
        expect(declarations(page_blocks[:dark]).keys).to match_array(declarations(page_blocks[:light]).keys)

        page_blocks.each do |theme, block|
          home = declarations(self.class.theme_blocks[theme])
          declarations(block).each do |token, value|
            expect(value).to eq(home[token]), "#{name}: #{token} (#{theme}) = #{value}, дім каже #{home[token].inspect}"
          end
        end
      end

      it "кожна вжита var() оголошена — неоголошена змінна малює прозорість без жодної помилки" do
        used = style.scan(/var\((--[\w-]+)\)/).flatten.uniq
        expect(used - declarations(page_blocks[:light]).keys).to be_empty
      end

      it "словник покриває решту available_locales, і кожен запис несе всі ключі розмітки" do
        markup_locale = doc.at_css("html")["lang"]
        expect(markup_locale).to eq(I18n.default_locale.to_s)
        expect(doc.at_css("title").text).to eq("Silken Net // #{markup.fetch('heading')}")
        expect(translations.keys).to match_array(I18n.available_locales.map(&:to_s) - [ markup_locale ])

        translations.each do |locale, strings|
          expect(strings.keys).to match_array(markup.keys), "#{name}/#{locale}"
          expect(strings.values).to all(be_present)
        end
      end

      next unless canon.key?(path.basename.to_s)

      it "каже те саме, що Errors::Page, словами errors.api.*" do
        translations.merge(I18n.default_locale.to_s => markup).each do |locale, strings|
          self.class.canon[name].each do |node, key|
            expect(strings[node]).to eq(I18n.t(key, locale: locale)), "#{name}/#{locale}/#{node}"
          end
        end
      end
    end
  end
end
