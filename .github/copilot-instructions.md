# Copilot Instructions — SilkenNet (Gaia 2.0)

## SSOT (must read before architecture decisions)
1. GitHub Wiki: https://github.com/Alexey-Lukin/silken_net/wiki
2. `docs/00_00_Gaia_2_0_System_Overview.md` … `docs/09_03_GitHub_Projects_and_Ops_Automation.md`
3. `README.md`

If any source conflicts, follow newer numbered docs (`00_00` → `09_03`) and Wiki.

## Project snapshot (current)
- Bio-IoT D-MRV platform for planetary-scale forest monitoring.
- Edge: STM32WLE5JC soldier nodes, LoRa mesh, Queen gateways, CoAP uplink.
- Energy: EBFC + BQ25570 MPPT + EDLC supercapacitor architecture.
- Backend: Rails 8.1, Ruby 4.0.2, PostgreSQL multi-DB, Sidekiq strict-priority queues.
- API: `/api/v1`, current documented surface is 82 unique endpoints.
- Web3: 12-chain architecture with Polygon as primary execution chain.

## Non-negotiable engineering rules
- Use Ruby **4.0.2** (`/opt/hostedtoolcache/Ruby/4.0.2/x64/bin` in PATH).
- Use `db/structure.sql` (not `schema.rb`).
- Keep controllers thin; business logic in services/workers.
- Respect queue priority order: `uplink > alerts > critical > downlink > default > web3_critical > web3 > web3_low > low`.
- For frontend work, read `docs/04_04_Phlex_UI_and_Tailwind.md` first.
- Prefer documented architecture from docs over old assumptions in prompts.

## Validation before finish
- `bundle exec rubocop`
- `bundle exec rspec` (if DB/services are available in the environment)
- Security checks when relevant: `bundle exec brakeman`, `bundle exec bundler-audit check`

## Important status caveat
Do not present documented BLOCKER items in docs as “implemented” unless code and docs both confirm closure.
