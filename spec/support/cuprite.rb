# frozen_string_literal: true

# Cuprite — headless Chrome driver for Capybara via Chrome DevTools Protocol.
# 2-5x faster than Selenium because it talks directly to Chrome (no Java middleman).
# https://github.com/rubycdp/cuprite
require "capybara/cuprite"

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1440, 900 ],
    browser_options: {
      "no-sandbox": nil,
      "disable-gpu": nil,
      "disable-dev-shm-usage": nil
    },
    process_timeout: 15,
    inspector: ENV["INSPECTOR"].present?,
    headless: ENV.fetch("HEADLESS", "true") != "false"
  )
end

Capybara.default_driver    = :rack_test
Capybara.javascript_driver = :cuprite
