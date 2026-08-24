# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# =============================================================================
# Afterlife Economy — Puro.earth Biomass Passport Worker
# =============================================================================
# When a tree dies and its wood is extracted (biomass_extraction), this worker
# generates a D-MRV (Digital Measurement, Reporting and Verification) payload —
# a "Biomass Passport" — proving the origin and quantity of dead wood destined
# for Biochar CORC generation on Puro.earth.
#
# The passport anchors: tree DID, GPS coordinates, biomass yield, extraction
# date, and a SHA-256 hash of lifetime telemetry for tamper-proof provenance.
#
# Three-phase orchestration [PERF.1(д), присуд founder 2026-08-20 — «третя форма»]:
# 1. On-chain anchoring via PuroEarth::PassportService → Polygon D-MRV Registry (:sent)
# 2. Receipt confirmation via PuroEarthConfirmationWorker → власний lifecycle на
#    `MaintenanceRecord#biomass_passport_status` (прецедент EthereumAnchor; поллер
#    після :confirmed re-enqueue'ить ЦЕЙ воркер — оркестратор один, фази ідемпотентні)
# 3. REST API submission via PuroEarth::RegistryApiService → Puro.earth CORC,
#    гейтована на :confirmed — on_chain_proof не віддається в зовнішній реєстр,
#    доки receipt не доведено (доти нога вела в `blockchain_transactions`, куди
#    паспортний хеш не потрапляє ніколи, і «доказ» їхав без перевірки revert)
#
# ⚠️ Позначена стеля: sent-limbo після crash ОБОХ воркерів (persist :sent + втрачений
# enqueue + вичерпані ретраї цього воркера) не має sweeper-крона — власний stuck-sweep
# відкладено до активації шляху (`ORACLE_PURO_PRIVATE_KEY`); recovery = console
# re-enqueue. Дім residual'а → `00_07` ARCH.66 (там же дві сестринські форми
# того самого lifecycle — грошова й Ethereum-анкерна).
# =============================================================================
class PuroEarthPassportWorker
  include ApplicationWeb3Worker
  sidekiq_options queue: "web3", retry: 5

  # [E.20] Заявка на CORC незворотна й іде в ЗОВНІШНІЙ реєстр, а Evidence Protocol
  # моделі `biomass_extraction` не покриває (`evidence_backed?` = repair+installation).
  class MissingEvidence < StandardError; end
  # [E.20, ⚖️ founder 2026-08-24] Друга умова тих самих воріт, і вона СВІДОМО стоїть
  # тут, а не на створенні: атестатор не мусить бути поруч у мить роботи в полі —
  # драбинка «фото на вході, незалежний підпис перед виходом у ЗОВНІШНІЙ реєстр»
  # дає йому вікно. Вимога на створенні штовхала б до профанації (підпише
  # найближчий колега, не дивлячись).
  class MissingAttestation < StandardError; end

  def perform(maintenance_record_id)
    record = MaintenanceRecord.find(maintenance_record_id)
    tree   = record.maintainable

    unless tree.is_a?(Tree)
      Rails.logger.warn "🌿 [Puro.earth] Record ##{maintenance_record_id} maintainable is not a Tree, skipping."
      return
    end

    require_evidence!(record)

    payload = build_passport_payload(record, tree)

    # Phase 1: On-chain anchoring (Polygon D-MRV Registry).
    # [ARCH.53/PuroEarth] Ідемпотентно: skip re-anchor якщо tx_hash вже є (double-anchor guard
    # на retry-after-persist). Вузький residual — краш МІЖ broadcast і persist (tx_hash ще nil) →
    # retry re-anchor; payloadHash детермінований → це ІДЕНТИЧНИЙ дубль-proof (registry-noise, не
    # double-CORC, бо Phase 2 guard'иться corc_ref) — reconcile-only, як EVM :processing-orphan.
    if record.biomass_passport_tx_hash.blank?
      tx_hash = with_web3_error_handling("Polygon", "Puro.earth Passport for Tree #{tree.did}") do
        PuroEarth::PassportService.new(payload).anchor!
      end
      record.update!(biomass_passport_tx_hash: tx_hash, biomass_passport_status: :sent)
    end

    # Phase 2: receipt-полл. Планування ПОЗА anchor-guard [ARCH.53/B5] → краш між persist
    # і enqueue відновлюється на retry цього воркера (`unique_for` поллера дедуплікує).
    if record.biomass_passport_sent?
      PuroEarthConfirmationWorker.perform_in(30.seconds, record.id)

    # Phase 3: REST API submission — ЛИШЕ після on-chain confirmed (idempotent — skip if issued).
    elsif record.biomass_passport_confirmed? && record.puro_earth_corc_ref.blank?
      corc_ref = submit_to_puro_earth_api(payload, record.biomass_passport_tx_hash)
      record.update!(puro_earth_corc_ref: corc_ref) if corc_ref
    end
    # :failed / :manual_review — термінальні для оркестратора: поллер уже лишив
    # error-лог із console-рецептом, ре-ганяти фази немає по чому.

    Rails.logger.info "🌿 [Puro.earth] Biomass Passport pass complete. " \
                      "Tree #{tree.did}, yield: #{record.biomass_yield_kg} kg, " \
                      "tx: #{record.biomass_passport_tx_hash} (#{record.biomass_passport_status}), " \
                      "CORC: #{record.puro_earth_corc_ref || "pending"}"

    payload
  end

  private

  # [E.20] Гейт фотодоказу стоїть ТУТ — на місці незворотної дії, — а не на моделі,
  # і це присуд, не смак ([`00_07`](../../docs/00_07_Action_Plan_Tracker.md) E.20):
  # ⛔ додавання `biomass_extraction` у `evidence_backed?` зламало б тракт, бо
  # валідація біжить на КОЖЕН `save` (форму `on: :create` відкинуто, ARCH.91), а
  # обидва Puro-воркери роблять `update!` на вже-створеному записі. Найгірше —
  # `sidekiq_retries_exhausted` поллера кличе `escalate_biomass_passport!` усередині
  # `rescue`, тож `RecordInvalid` полетів би незловленим і запис завис би в `:sent`
  # назавжди з мертвим власним запобіжником.
  #
  # 🔴 Форма відмови — RAISE, а не тихий `return`, і носій обрано ВИМІРОМ, не смаком:
  # per-tree `EwsAlert(:field_audit)` тут був би зʼїдений — `TreeStalenessSweepWorker`
  # закриває такі алерти для дерев, що покинули `active`, а це дерево вже
  # `deceased` (його оголосив `EcosystemHealingWorker` до нас). Тобто ескалація
  # прожила б хвилини й зникла. Cluster-level теж хибний: він входить у
  # `dark_cluster_ids` і осліпив би per-tree dead-man switch на весь кластер.
  # Тому — гучний провал: 5 ретраїв (фото ще можуть додати) → DeadSet + Sentry,
  # де вже стоїть алерт `sn-alert-sidekiq-deadset`. Заявка не подається.
  #
  # ⚠️ Оголошена стеля: цей гейт стереже ОСТАННЮ ланку. `declare_deceased!` і
  # звʼязаний із ним `trigger_slashing_protocol` спрацювали РАНІШЕ, у
  # `EcosystemHealingWorker` — чи гейтувати і їх, лишається відкритим
  # ([`00_07`](../../docs/00_07_Action_Plan_Tracker.md) E.20).
  def require_evidence!(record)
    unless record.photos.any?
      Rails.logger.error "🌿 [Puro.earth] Record ##{record.id} (biomass_extraction) БЕЗ фотодоказу — " \
                         "заявку на CORC не подано. Дія: додати фото до запису й " \
                         "re-enqueue PuroEarthPassportWorker з консолі."
      raise MissingEvidence, "MaintenanceRecord ##{record.id}: biomass passport requires photo evidence"
    end

    return if record.attested?

    Rails.logger.error "🌿 [Puro.earth] Record ##{record.id} НЕ ЗААТЕСТОВАНИЙ — заявку на CORC не подано. " \
                       "Дія: інший форестер (НЕ автор запису) тисне «Засвідчити» на сторінці запису, " \
                       "далі re-enqueue PuroEarthPassportWorker з консолі."
    raise MissingAttestation, "MaintenanceRecord ##{record.id}: biomass passport requires an independent attestation"
  end

  # Phase 2: Submit passport to Puro.earth REST API for CORC issuance.
  # Non-blocking: REST API failure does NOT invalidate on-chain anchoring.
  # The on-chain proof (tx_hash) is already recorded, so CORC can be
  # resubmitted manually or via retry if API is temporarily unavailable.
  def submit_to_puro_earth_api(payload, tx_hash)
    PuroEarth::RegistryApiService.new(payload, tx_hash: tx_hash).submit!
  rescue PuroEarth::RegistryApiService::SubmissionError => e
    Rails.logger.warn "🌿 [Puro.earth] REST API submission failed (on-chain anchoring succeeded): #{e.message}"
    nil
  end

  def build_passport_payload(record, tree)
    {
      tree_did: tree.did,
      biomass_yield_kg: record.biomass_yield_kg.to_f,
      extraction_date: record.performed_at.iso8601,
      gps_coordinates: {
        latitude: record.latitude&.to_f || tree.latitude&.to_f,
        longitude: record.longitude&.to_f || tree.longitude&.to_f
      },
      lifetime_telemetry_hash: compute_telemetry_hash(tree)
    }
  end

  def compute_telemetry_hash(tree)
    digest_input = "#{tree.did}:#{tree.telemetry_logs.count}:#{tree.created_at.to_i}"
    Digest::SHA256.hexdigest(digest_input)
  end
end
