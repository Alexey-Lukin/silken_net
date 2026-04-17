# Gaia 2.0 Guide for Claude

## Read order (mandatory)
1. Wiki SSOT: https://github.com/Alexey-Lukin/silken_net/wiki
2. `docs/00_00_...` to `docs/09_03_...`
3. `README.md`

## Core context
SilkenNet is a planetary-scale bio-IoT D-MRV system:
- Ti-6Al-4V gyroid anchor + EBFC energy harvesting
- Soldier STM32WLE5JC nodes, LoRa mesh, Queen gateway, CoAP uplink
- Rails 8.1 backend with Sidekiq, PostgreSQL, Phlex/Turbo UI
- Proof-of-Growth + 12-chain Web3 stack (Polygon primary)

## Environment
```bash
export PATH="/opt/hostedtoolcache/Ruby/4.0.2/x64/bin:$PATH"
ruby --version  # must be 4.0.2
```

## Repository rules
- Use `structure.sql` with migrations.
- Keep domain logic in services/workers, not fat controllers/models.
- Respect strict queue priorities.
- Frontend tasks must follow `docs/04_04_Phlex_UI_and_Tailwind.md`.
- Treat docs BLOCKER sections as active constraints unless explicitly resolved in code/docs.

## Validation commands
```bash
bundle exec rubocop
bundle exec rspec
bundle exec brakeman
bundle exec bundler-audit check
```
