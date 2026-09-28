# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [SEC.3] Конвеєр пише Flash рядками `-w32 <addr> <w0> <w1> …` — цілими
# doubleword'ами (FactoryFlashing::CommandBuilder#flash_write_commands), тож
# специ звіряють не окремі рядки, а образ Flash, який транскрипт лишає:
# { адреса => слово }. Приймає і команди, і лог шима (той самий arg-vector).
module FlashImageHelper
  def flash_image(commands)
    commands.grep(/ -w32 /).each_with_object({}) do |cmd, image|
      addr, *words = cmd.split(" -w32 ", 2).last.split
      words.each_with_index { |word, i| image[Integer(addr, 16) + (4 * i)] = word }
    end
  end
end

RSpec.configure do |config|
  config.include FlashImageHelper, file_path: %r{spec/services/factory_flashing/}
end
