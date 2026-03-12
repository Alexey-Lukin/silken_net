# frozen_string_literal: true

# = ===================================================================
# 📘 Blueprinter — Конфігурація JSON серіалізатора
# = ===================================================================
# Blueprinter підтримує кастомні JSON генератори.
# Використовуємо Oj напряму для максимальної швидкості серіалізації
# API-відповідей (26 контролерів, 8 блупрінтів).

# Blueprinter використовує generator.generate(hash) для серіалізації —
# Oj.generate() є drop-in заміною для JSON.generate() з вищою швидкістю.
# Див.: Blueprinter::Configuration#jsonify → generator.public_send(:generate, blob)
Blueprinter.configure do |config|
  config.generator = Oj
end
