#!/usr/bin/env ruby
# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

#
# scripts/verify_lineage_bundle.rb — офлайн-верифікатор ISO lineage-bundle
# (ARCH.12/MRV.1). Pure Ruby, БЕЗ Rails/БД/мережі — аудитор ганяє його на
# власній машині проти bundle-файлу і довіряє лише on-chain кореням.
#
# Крипто-перевірки (все — з самого файлу):
#   1. leaf_cid == CidGenerator.cidv1(canonical payload)  (цілісність вмісту)
#   2. payload.device_uid == tx.tree_did і payload.telemetry_log_id == leaf-id
#      (лист не «переїхав» з чужого дерева/запису)
#   3. sealed-кредит: MerkleTree.root(own-window листя) == telemetry_merkle_root
#      (набір і порядок листя прив'язані до кредиту, не issuer-asserted)
#   4. tier1: leaf_cid + path → ПЕРЕРАХОВАНИЙ субкорінь == заявленому
#   5. tier2: субкорінь + path → state_root якоря
#   6. форма листа за версією (lib/leaf_payload_shape.rb): точні ключі v1/v2, у v2 — DID у перших
#      4 байтах сирого кадру = device_uid; невідома версія — відмова; той самий сирий кадр під
#      РІЗНИМИ листами — відмова (той самий лист легально стоїть у кількох кредитах; ловить
#      ДОСЛІВНИЙ повтор — кадр, що виглядає унікальним, власник ключа вигадає)
#   7. версія: схема v1 не несе листя v2, схема v2 — несе; мітка sealed-кредиту lineage_version =
#      найвища версія його own-window листя
#   8. один telemetry_log_id на весь бандл — один leaf_cid (рядок незмінний, тож спільний лист
#      завжди той самий); у межах кредиту лист не повторюється; «sealed» виводиться з наявності
#      кореня, а мітка `seal`, що з ним розходиться, — відмова (інакше «unsealed» минав би 3 і 7)
#   9. [FW.66 (Б) · S8b] вміст листа v2 понад кадр: бали = 0 або формула v2 від ema_delta_t_s
#      (заморожена разом із версією листа; нуль при додатній формулі — «утримано», рахується);
#      конверти QATT (секція `qatt_envelopes`, лише схема v2): sha256 = хеш байтів, рамка конверта,
#      Ed25519-підпис Королеви над ним і її UID (OpenSSL, строгий S < L — самоперевірка на векторі
#      RFC 8032 перед першим конвертом); кожен v2-лист із хешем знаходить свій конверт, зайвий
#      конверт — відмова; запис реєстрації ключа (якщо є) — той самий ключ і до прийому конверта
#  10. [ARCH.122] печатка ланцюга організації: голова → корінь голів (поле ланцюга в рядку
#      агрегату), SHA256(рядок агрегату) = leaf0 → tier2-шлях → state_root якоря
#
# Межа довіри (свідома, задекларована): amount, ПОВНОТА набору кредитів/листя і
# континуїтет вікон — issuer-asserted (backstop = org AuditLog-ланцюг; leaf0 якоря запечатує голови
# УСІХ ланцюгів, і бандл несе шлях від голови своєї організації — крок 10, ARCH.122). Лист v2
# зобовʼязує щодо ІДЕНТИЧНОСТІ кадру ефіру, не щодо виміру: кадр — шифртекст сесійним
# ключем вузла, який ратчет знищує, тож MIC і вміст перевіряє лише власник ключа, поки той живий.
# Підпис конверта доводить, що його підписав ключ, НАЗВАНИЙ у бандлі; що це ключ Королеви — звір
# `key_registration` з експортом AuditLog організації: голову її ланцюга на мить якоря крок 10
# перевіряє з файлу, а що запис реєстрації — предок цієї голови, бачить лише експорт.
# Що кадр листа лежить усередині конверта — issuer-asserted: шифртекст під ключем Королеви.
# [DOC-T.89] `insurance_payouts` — емісія за ЗБИТОК, НЕ вуглецеві кредити: крипто під
# нею немає за конструкцією (немає листя), тож тут вона лише ПЕРЕЛІЧУЄТЬСЯ вголос.
# Мовчазна секція гірша за відсутню: аудитор прийняв би її за перевірену.
# On-chain звірка state_root — людина: tx МУСИТЬ таргетити канонічний
# StateRootAnchor-контракт; адресу `anchor_contract` звіряй з НЕЗАЛЕЖНИМ
# джерелом (канон проєкту / офіційний сайт), не з цим файлом.
#
# Usage: ruby scripts/verify_lineage_bundle.rb bundle.json
# Exit: 0 = всі крипто-перевірки пройшли; 1 = будь-який mismatch.
#

require "json"
require "digest"
require "bigdecimal"
require "time"
require_relative "../lib/merkle_tree"
require_relative "../app/services/filecoin/cid_generator"
require_relative "../lib/leaf_payload_shape"
require_relative "../lib/qatt_envelope_signature"

abort "Usage: ruby scripts/verify_lineage_bundle.rb <bundle.json>" if ARGV.empty?

# Анти-smuggling: JSON з дубль-ключами (людина бачить перший, парсер бере
# останній) відкидається на вході — класика атак на JSON-верифікатори.
# ДВОШАРОВО: json ≥ 2.20 — нативний `allow_duplicate_key: false` (C-парсер
# дедуплікує ДО виклику []=, тож object_class-override там СЛІПИЙ — fable №2
# емпірично); старші json опцію мовчки ігнорують, але їхній парсер кличе []=
# на кожен ключ → StrictHash ловить. Захист не залежить від версії на машині
# аудитора.
class StrictHash < Hash
  def []=(key, value)
    raise JSON::ParserError, "duplicate JSON key: #{key.inspect}" if key?(key)

    super
  end
end

begin
  bundle = JSON.parse(File.read(ARGV[0]), object_class: StrictHash, allow_duplicate_key: false)
rescue JSON::ParserError => e
  abort "✗ Bundle відхилено: #{e.message}"
end
SCHEMAS = %w[silken.mrv.lineage.v1 silken.mrv.lineage.v2].freeze
abort "Невідома схема: #{bundle['schema']}" unless SCHEMAS.include?(bundle["schema"])

failures = []
anchored = 0
pending = 0
regrouped = 0
diverged = 0
total_leaves = 0
sealed_credits = 0
unsealed_credits = 0
roots_to_check = {}
raw_seen = {}
id_cid = {}
max_seen = nil
v2_payloads = {} # leaf_cid → payload: той самий лист у кількох кредитах рахується раз

bundle.fetch("credits").each do |credit|
  tx_id = credit.dig("tx", "id")
  tree_did = credit.dig("tx", "tree_did")

  credit.fetch("leaves").each do |leaf|
    total_leaves += 1
    log_id = leaf.fetch("telemetry_log_id")
    payload = leaf.fetch("payload")

    # 1. Цілісність payload → CID
    recomputed_cid = Filecoin::CidGenerator.cidv1(payload)
    unless recomputed_cid == leaf.fetch("leaf_cid")
      failures << "tx #{tx_id} / log #{log_id}: payload → CID mismatch (#{recomputed_cid} ≠ #{leaf['leaf_cid']})"
      next
    end

    # 2. Лист прив'язаний до дерева кредиту і до власного запису
    unless payload["device_uid"] == tree_did
      failures << "tx #{tx_id} / log #{log_id}: payload.device_uid #{payload['device_uid'].inspect} ≠ tx.tree_did #{tree_did.inspect}"
    end
    unless payload["telemetry_log_id"] == log_id
      failures << "tx #{tx_id} / log #{log_id}: payload.telemetry_log_id #{payload['telemetry_log_id'].inspect} ≠ leaf-id"
    end
    # 6. Форма за версією й повтор сирого кадру (той самий лист легально стоїть у кількох кредитах —
    # повтор це той самий КАДР під РІЗНИМИ листами, тобто під іншим leaf_cid)
    LeafPayloadShape.errors(payload).each { |err| failures << "tx #{tx_id} / log #{log_id}: #{err}" }
    version = LeafPayloadShape.version_of(payload)
    max_seen = [ max_seen, version ].compact.max if version.is_a?(Integer)
    v2_payloads[leaf["leaf_cid"]] = payload if version == 2 && LeafPayloadShape.errors(payload).empty?
    # 8. Той самий запис — завжди той самий лист
    first_cid_for_id = (id_cid[log_id] ||= leaf["leaf_cid"])
    failures << "tx #{tx_id} / log #{log_id}: той самий запис стоїть під іншим листом" unless first_cid_for_id == leaf["leaf_cid"]
    if (raw = payload["raw_record"])
      first_cid = (raw_seen[raw] ||= leaf["leaf_cid"])
      failures << "tx #{tx_id} / log #{log_id}: сирий кадр уже стоїть під іншим листом — повтор кадру" unless first_cid == leaf["leaf_cid"]
    end

    proof = leaf.fetch("anchor_proof")
    case proof.fetch("status")
    when "pending_anchor" then pending += 1
    when "unprovable_regrouped" then regrouped += 1
    when "subroot_diverged"
      # [ARCH.70 ⚖️ 2026-08-29] Окремий рахунок, але НЕ падіння — і це присуд,
      # не поблажливість. Розбіжність субкореня однаково настає від легітимного
      # переїзду дерева між кластерами і від підміни payload'а; емітент причину
      # не ізолює (стеля названа в `Mrv::LineageReportService`). Падати на
      # неоднозначному факті означало б стверджувати tamper без доказу — рівно
      # той клас, проти якого будувався весь тракт.
      diverged += 1
    when "anchored"
      # 4. tier1: перерахований субкорінь МУСИТЬ збігтись із заявленим (анти-підміна ярусу)
      claimed_subroot = proof.dig("tier1", "subroot")
      unless MerkleTree.verify(leaf["leaf_cid"], proof.dig("tier1", "path"), claimed_subroot)
        failures << "tx #{tx_id} / log #{log_id}: tier1 path не веде до заявленого субкореня"
        next
      end
      # 5. tier2: субкорінь → state_root
      state_root = proof.dig("anchor", "state_root")
      unless MerkleTree.verify(claimed_subroot, proof.dig("tier2", "path"), state_root)
        failures << "tx #{tx_id} / log #{log_id}: tier2 path не веде до state_root якоря"
        next
      end
      anchored += 1
      roots_to_check[state_root] = proof.dig("anchor", "etherscan_url")
    else
      failures << "tx #{tx_id} / log #{log_id}: невідомий proof-статус #{proof['status']}"
    end
  end

  # 3. Sealed-кредит: mint-root перераховується з own-window листя (канонічний порядок
  # = порядок масиву; підміна набору/порядку/листа → mismatch)
  # 8. Лист не повторюється в межах кредиту; «sealed» — це наявний корінь, а не мітка з файлу
  repeated = credit["leaves"].map { |l| l["leaf_cid"] }.tally.select { |_cid, n| n > 1 }.keys
  failures << "tx #{tx_id}: лист повторюється в межах кредиту (#{repeated.size})" if repeated.any?
  sealed = !credit["telemetry_merkle_root"].nil?
  unless credit["seal"] == (sealed ? "sealed" : "unsealed")
    failures << "tx #{tx_id}: мітка seal #{credit['seal'].inspect} розходиться з коренем (#{sealed ? 'є' : 'немає'})"
  end
  if sealed
    sealed_credits += 1
    own = credit["leaves"].select { |l| l["window_source"] == tx_id }
    own_cids = own.map { |l| l["leaf_cid"] }
    # 7. Мітка кредиту — найвища версія ЙОГО листя (не константа емітента)
    own_max = own.map { |l| LeafPayloadShape.version_of(l.fetch("payload")) }.grep(Integer).max
    unless credit["lineage_version"] == own_max
      failures << "tx #{tx_id}: lineage_version #{credit['lineage_version'].inspect} ≠ найвища версія own-window листя #{own_max.inspect}"
    end
    recomputed_root = MerkleTree.root(own_cids)
    unless recomputed_root == credit["telemetry_merkle_root"]
      failures << "tx #{tx_id}: mint-root mismatch (перераховано #{recomputed_root.inspect}, " \
                  "заявлено #{credit['telemetry_merkle_root'].inspect}) — набір/порядок листя " \
                  "підмінено АБО пізній commit/ретеншн-дроп (05_04 GRACE-residual)"
    end
  else
    unsealed_credits += 1
  end
end

# 7. Схема бандла ⟷ версії листя: v1-схема без v2-листя, v2-схема — з ним
if (bundle["schema"] == "silken.mrv.lineage.v2") != (max_seen == 2)
  failures << "схема #{bundle['schema']} не відповідає листю (найвища версія листа #{max_seen.inspect})"
end

# 9. Конверти QATT: лише схема v2 їх несе, і несе рівно ті, на які посилається її листя
envelopes = bundle["qatt_envelopes"]
if bundle["schema"] == "silken.mrv.lineage.v2"
  failures << "схема v2 без масиву qatt_envelopes" unless envelopes.is_a?(Array)
elsif !envelopes.nil?
  failures << "схема #{bundle['schema']} несе qatt_envelopes"
end
envelopes = [] unless envelopes.is_a?(Array)
if envelopes.any? && !QattEnvelopeSignature.self_test
  abort "✗ Самоперевірка Ed25519 не пройшла (вектор RFC 8032 і відмова мутації S + L) — " \
        "OpenSSL цієї машини не годиться для перевірки підписів Королеви."
end

# Час, який лист ЗАПЕЧАТУЄ (created_at у payload під CID), — єдиний якір дати, що його емітент
# заднім числом не пересуне; `received_at` і дата запису реєстрації — його ж твердження. Допуск —
# розбіжність годинників хостів (прийом, воркер, фабрика): хибна відмова заякореного бандла була б
# вічною, а п'ять хвилин атаці «зареєструвати ключ після листа» нічого не дають.
CLOCK_SKEW_S = 300
leaves_by_envelope = v2_payloads.values.select { |p| p["qatt_envelope_sha256"] }.group_by { |p| p["qatt_envelope_sha256"] }
envelope_shas = {}
unregistered = 0
foreign_org = 0
envelopes.each_with_index do |env, i|
  unless env.is_a?(Hash)
    failures << "qatt_envelopes[#{i}] не є обʼєктом JSON"
    next
  end
  sha = env["sha256"]
  label = "конверт #{sha.to_s[0, 16]}…"
  unless sha.is_a?(String) && sha.match?(LeafPayloadShape::SHA256_HEX) && sha == sha.downcase &&
         env["envelope"].is_a?(String) && env["envelope"].match?(/\A(?:\h\h)+\z/) && env["envelope"] == env["envelope"].downcase
    failures << "#{label}: sha256 / envelope не нижній hex"
    next
  end
  failures << "#{label}: повторюється в секції" if envelope_shas.key?(sha)
  envelope_shas[sha] = true
  bytes = [ env["envelope"] ].pack("H*")
  failures << "#{label}: sha256 ≠ хеш байтів конверта" unless QattEnvelopeSignature.sha256(bytes).unpack1("H*") == sha
  failures << "#{label}: рамка конверта QATT v2 не ціла" unless QattEnvelopeSignature.shape_ok?(bytes)
  unless QattEnvelopeSignature.verify(bytes, uid: env["gateway_uid"], public_key_hex: env["public_key_hex"])
    failures << "#{label}: підпис Королеви #{env['gateway_uid'].inspect} ключем #{env['public_key_hex'].to_s[0, 16]}… не сходиться"
  end

  leaves = leaves_by_envelope.fetch(sha, [])
  # Кожен CCM-запис займає в шифртексті 31 Б (кадр ефіру + RSSI), тож листів на конверт не більше.
  capacity = [ bytes.bytesize - QattEnvelopeSignature::MIN_LEN, 0 ].max / 31
  failures << "#{label}: несе щонайбільше #{capacity} CCM-записів, а листів на нього #{leaves.size}" if leaves.size > capacity
  first_leaf_at = leaves.map { |p| Time.iso8601(p["created_at"].to_s) }.min
  if first_leaf_at && Time.iso8601(env["received_at"].to_s) > first_leaf_at + CLOCK_SKEW_S
    failures << "#{label}: прийом заявлено ПІЗНІШЕ за найраніший лист, що на конверт посилається"
  end

  registration = env["key_registration"]
  if registration.nil?
    unregistered += 1
  elsif !registration.is_a?(Hash)
    failures << "#{label}: key_registration не є обʼєктом JSON"
  elsif registration["gateway_uid"] != env["gateway_uid"] || registration["public_key_hex"] != env["public_key_hex"]
    failures << "#{label}: запис реєстрації ##{registration['audit_log_id']} — інший шлюз або ключ, ніж підписав конверт"
  else
    foreign_org += 1 unless registration["organization_id"] == bundle.dig("organization", "id")
    if first_leaf_at && Time.iso8601(registration["created_at"].to_s) > first_leaf_at + CLOCK_SKEW_S
      failures << "#{label}: ключ зареєстровано ПІЗНІШЕ за найраніший лист, що на конверт посилається (##{registration['audit_log_id']})"
    end
  end
rescue ArgumentError, TypeError => e
  failures << "конверт #{env.is_a?(Hash) ? env['sha256'].to_s[0, 16] : i}…: #{e.message}"
end
shas_in_order = envelopes.map { |e| e.is_a?(Hash) ? e["sha256"].to_s : "" }
failures << "qatt_envelopes не впорядковано за sha256" unless shas_in_order == shas_in_order.sort

referenced = leaves_by_envelope.keys
(referenced - envelope_shas.keys).each { |sha| failures << "лист посилається на конверт #{sha[0, 16]}…, якого бандл не несе" }
(envelope_shas.keys - referenced).each { |sha| failures << "конверт #{sha[0, 16]}… — на нього не посилається жоден лист" }
without_envelope = v2_payloads.values.count { |p| p["qatt_envelope_sha256"].nil? }
held = v2_payloads.values.count { |p| LeafPayloadShape.v2_points_held?(p) }

# 10. [ARCH.122] Печатка ланцюга організації на кожному якорі, на який спирається бандл:
# голова її ланцюга → корінь голів (поле ланцюга в рядку агрегату), SHA256(рядок) = leaf0,
# leaf0 → state_root. Що key_registration — предок цієї голови, файл не несе: звір експорт AuditLog.
chains_sealed = 0
chains_absent = 0
anchored_roots = roots_to_check.keys # лише ті, на які спираються листи (печатки додаються нижче)
seal_roots = []
Array(bundle["audit_chain_seals"]).each do |seal|
  seal_roots << seal["state_root"]
  label = "печатка ланцюга / якір ##{seal['anchor_id']}"
  case seal["status"]
  when "no_chain_at_anchor"
    chains_absent += 1
  when "sealed"
    payload = seal["aggregate_payload"].to_s
    fields = payload.split("|", -1)
    if fields.size != 6 || fields[3] !~ /\A(?:\h{64}|GENESIS)\z/
      failures << "#{label}: рядок агрегату не тієї форми (6 полів, поле ланцюга — 64 hex)"
    elsif seal["organization_id"] != bundle.dig("organization", "id")
      failures << "#{label}: печатка іншої організації (#{seal['organization_id'].inspect})"
    elsif !MerkleTree.verify("#{seal['organization_id']}|#{seal['chain_head']}", Array(seal["chain_path"]), fields[3])
      failures << "#{label}: голова ланцюга не веде до кореня голів у рядку агрегату"
    elsif !MerkleTree.verify(Digest::SHA256.hexdigest(payload), Array(seal["tier2_path"]), seal["state_root"])
      failures << "#{label}: рядок агрегату не веде до state_root якоря"
    else
      chains_sealed += 1
      roots_to_check[seal["state_root"]] ||= nil
    end
  else
    failures << "#{label}: невідомий статус #{seal['status'].inspect}"
  end
end
# Печатка — на КОЖЕН якір, на який спираються листи, і лише на них: інакше емітент пропустив би
# печатку чи підклав чужу, а ✓ однаково обіцяв би «ланцюг запечатано».
(anchored_roots - seal_roots).each { |root| failures << "якір #{root.to_s[0, 16]}…: листи на нього спираються, а печатки ланцюга в бандлі немає" }
(seal_roots - anchored_roots).uniq.each { |root| failures << "печатка ланцюга для якоря #{root.to_s[0, 16]}…, на який не спирається жоден лист" }
failures << "audit_chain_seals: на один якір — одна печатка" if seal_roots.size != seal_roots.uniq.size

puts "── Lineage bundle: #{bundle['credits'].size} credits " \
     "(org #{bundle.dig('organization', 'id')}, #{bundle.dig('period', 'from')}..#{bundle.dig('period', 'to')})"
puts "   leaves anchored=#{anchored} pending_anchor=#{pending} unprovable_regrouped=#{regrouped} subroot_diverged=#{diverged} · " \
     "credits sealed=#{sealed_credits} unsealed=#{unsealed_credits}"
if chains_sealed.positive? || chains_absent.positive?
  puts "   ланцюг AuditLog організації: запечатано якорями=#{chains_sealed} · без ланцюга на мить якоря=#{chains_absent}. " \
       "⚠️ Що key_registration — предок запечатаної голови, звір з експортом AuditLog (ланцюга файл не несе); " \
       "«без ланцюга на мить якоря» — заява емітента, файл її не доводить."
end
if v2_payloads.any?
  puts "   v2: листів=#{v2_payloads.size} · бали утримано=#{held} (причину лист не несе) · " \
       "без конверта=#{without_envelope} (батч не атестовано) · конвертів=#{envelopes.size} · " \
       "ключ без запису реєстрації=#{unregistered} · Королев інших організацій=#{foreign_org}"
  puts "   ⚠️  Підпис конверта доводить ключ, НАЗВАНИЙ у бандлі. Що він Королевин — звір key_registration " \
       "з експортом AuditLog організації (для Королеви іншої організації — з ЇЇ експортом); вхід " \
       "ema_delta_t_s і бали — твердження сервера (перевірено лише їхню узгодженість за формулою v2); " \
       "що кадр листа лежить у конверті — issuer-asserted."
  if unregistered.positive?
    puts "   ⚠️  #{unregistered} конверт(и) без запису реєстрації ключа: їхній підпис доводить лише " \
         "самоузгодженість бандла — емітент, що вигадав рядки, вигадав би й ключ."
  end
end

# [DOC-T.89] Страхові виплати: НЕ верифікуються (нічого верифікувати) — але й НЕ
# замовчуються. М'яке читання замість `fetch` свідомо: bundle без секції (старіший
# випуск) лишається валідним, а не падає на відсутньому ключі.
payouts = bundle["insurance_payouts"]
payouts = [] unless payouts.is_a?(Array)
if payouts.any?
  # 💰 Сума ГРУПУЄТЬСЯ за `token_type` і друкується З ОДИНИЦЕЮ: рядки різних токенів —
  # різні шкали, і зведення їх в одне число тут було б тим самим класом дефекту, який
  # ця секція лікує ярусом вище. BigDecimal, а не Float: це аудиторський артефакт.
  totals = payouts.group_by { |p| p.dig("tx", "token_type") }
                  .map { |token, rows| "#{rows.sum { |r| BigDecimal(r.dig('tx', 'amount').to_s) }.to_s('F')} #{token}" }
                  .join(" + ")
  puts "   ⚠️  insurance_payouts=#{payouts.size} (Σ #{totals}): емісія за ЗБИТОК, НЕ вуглецеві " \
       "кредити — lineage під ними НЕМАЄ за конструкцією, крипто-перевірок тут НУЛЬ. " \
       "On-chain вони несуть префікс `INS_`; звіряй суму з subgraph " \
       "`ProtocolFinancials.totalMintedInsurance`."
end

if unsealed_credits.positive?
  puts "   ⚠️  #{unsealed_credits} unsealed-кредит(и): mint-root-binding для них НЕ перевірявся " \
       "(nil-root = легітимний fail-open, але аудит мусить це БАЧИТИ, не пропустити мовчки)."
end

if anchored.zero? && total_leaves.positive?
  puts "   ⚠️  ЖОДЕН лист не заякорений — ланцюг до on-chain кореня НЕ перевірявся " \
       "(pending/regrouped-статуси легітимні для свіжих даних, але аудит без якоря неповний)."
end

unless roots_to_check.empty?
  contract = bundle["anchor_contract"]
  puts "   Звір state_root(и) on-chain сам (StateRootAnchor):"
  puts "   ⚠️  tx МУСИТЬ таргетити контракт #{contract || '(anchor_contract не задано — pre-deploy)'}" \
       " — адресу звіряй з НЕЗАЛЕЖНИМ джерелом (канон/сайт), не з цим файлом."
  roots_to_check.each { |root, url| puts "     #{root} → #{url || '(tx ще без etherscan-URL)'}" }
end

if failures.any?
  puts "✗ CRYPTO MISMATCH (#{failures.size}):"
  failures.each { |f| puts "   · #{f}" }
  exit 1
end

envelope_claim = envelopes.any? ? " + підписи конвертів QATT" : ""
envelope_claim += " + печатка ланцюга AuditLog" if chains_sealed.positive?
envelope_claim += " (#{unregistered} — без дати реєстрації ключа)" if unregistered.positive?
puts "✓ Всі крипто-перевірки пройшли (leaf-CID + did-binding + mint-root + tier1 + tier2#{envelope_claim})."
exit 0
