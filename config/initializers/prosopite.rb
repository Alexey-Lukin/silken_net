# frozen_string_literal: true

# Prosopite — N+1 query detector для development та test середовищ.
# Автоматично виявляє N+1 запити та попереджає розробника.
# Сучасна альтернатива Bullet, сумісна з Rails 8+.
if defined?(Prosopite)
  Prosopite.raise = Rails.env.test?
  Prosopite.stderr_logger = Rails.env.development?
  Prosopite.prosopite_logger = Rails.env.development?
  Prosopite.min_n_queries = 2
end
