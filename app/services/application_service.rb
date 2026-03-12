# frozen_string_literal: true

# = ===================================================================
# 🏗️ APPLICATION SERVICE (Base Class for All Service Objects)
# = ===================================================================
# Уніфікований фундамент для всіх сервісних об'єктів SilkenNet.
# Забезпечує:
# - Стандартний інтерфейс виклику через .call (делегує до #perform)
# - Структурований шаблон для нових сервісів
#
# Використання:
#   class MyService < ApplicationService
#     def initialize(param1, param2)
#       @param1 = param1
#       @param2 = param2
#     end
#
#     def perform
#       # бізнес-логіка
#     end
#   end
#
#   MyService.call(param1, param2)
class ApplicationService
  def self.call(...)
    new(...).perform
  end
end
