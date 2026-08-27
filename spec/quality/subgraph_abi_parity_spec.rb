# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "spec_helper"
require "json"
require "yaml"
require_relative "../support/repo_root"

# 🔴 `subgraph/abis/*.json` не синхронізувалися з `contracts/` НІЧИМ — ні скриптом, ні
# гейтом, ні CI-кроком (виміряно 2026-08-27: `grep -rl "abis/" scripts/ lib/tasks/
# .github/workflows/` → нуль).
#
# Чому це тихо ОБАБІЧ. `graph codegen`/`graph build` компілюють мапінг проти ABI, що
# лежить у теці, тож застарілий ABI дає **зелену збірку над неправильним контрактом**:
# субграф просто не побачить нової події або прочитає стару сигнатуру, а індекс — це
# поверхня, з якої ESG-покупець і ISO-аудитор читають нашу емісію. Сусідній гейт цього
# не накриває за ОГОЛОШЕНОЮ стелею: `solidity_signature_arity_check` судить
# `contracts/*.sol` ⟷ `docs/**`, і `subgraph/` у його глоби не входить узагалі — тобто
# канон від дрейфу сигнатур захищений, а аудиторська поверхня ні. Прецедент реальний:
# `archiveRoot` свого часу проїхав у контракти й `subgraph.yaml`, лишивши канон на
# чотирипараметричній формі у двадцяти місцях.
#
# 🔒 CEILING — і вона ВИМІРЯНА, а не припущена. Наївний напрям «усе, що в ABI, мусить
# бути в наших `.sol`» має **0% точності**: 21 із 21 хіта — успадковані події
# OpenZeppelin (`Transfer`, `Approval`, `Paused`, `RoleGranted`, `EIP712DomainChanged`,
# `DelegateChanged`…), які в ABI законні, бо їх емітує скомпільований контракт, і яких
# у нашому джерелі немає за побудовою. Тому судяться рівно три напрями, всі — від
# ТОГО, ЩО МИ ОГОЛОСИЛИ АБО ОБРОБЛЯЄМО:
#   (1) подія, ОГОЛОШЕНА в `contracts/*.sol`, мусить мати в ABI побайтово той самий
#       підпис (типи + `indexed`) — це і є «ABI протух після зміни контракту»;
#   (2) подія, яку субграф ОБРОБЛЯЄ, мусить існувати в ABI, що він для неї називає;
#   (3) вона ж мусить бути оголошена в нашому Solidity — інакше мапінг слухає подію,
#       якої контракт більше не емітує.
# Поза скоупом свідомо: функції та помилки ABI (субграф їх не читає), успадковані
# події, і СЕМАНТИКА мапінгу — компіляція судить типи, ніколи зміст (OPS.34).
#
# ⚠️ **І ще одна межа, куплена МУТАЦІЄЮ, а не виведена: імена параметрів не судяться.**
# Порівнюються `[тип, indexed]`, тож перейменування параметра в ABI лишає цей файл
# ЗЕЛЕНИМ — перевірено підсадкою. Це не пропуск: Solidity-оголошення й підпис The Graph
# імен не ділять (у другому їх немає взагалі), тож спільної осі для порівняння не існує.
# Клас закриває СУСІД: `graph codegen` робить із імен параметрів акцесори
# (`event.params.treeDidHash`), тож перейменування в ABI ламає компіляцію `mapping.ts` і
# червонить `CI · Subgraph`. Названо тут, бо «зелено» інакше читалося б ширше, ніж воно є.
module SubgraphAbiParity
  CONTRACTS_GLOB = "contracts/*.sol"
  MANIFEST       = REPO_ROOT.join("subgraph/subgraph.yaml")
  ABI_DIR        = REPO_ROOT.join("subgraph/abis")

  # `event Name(type [indexed] name, …);` — оголошення може займати кілька рядків.
  EVENT_DECL_RE = /^\s*event\s+(\w+)\s*\(([^;]*?)\)\s*;/m
  # Формат The Graph: `Name(indexed address,uint256,…)` — імена опущені, `indexed`
  # стоїть ПЕРЕД типом, тобто інший порядок токенів, ніж у Solidity. Обидва боки
  # нормалізуються в `[[type, indexed?], …]`, інакше порівнювались би два діалекти.
  HANDLER_RE = /event:\s*([A-Za-z0-9_]+)\(([^)]*)\)/

  module_function

  def normalize_solidity(args)
    args.split(",").map(&:strip).reject(&:empty?).map do |a|
      [ a.split(/\s+/).first, a.include?("indexed") ]
    end
  end

  def normalize_graph(sig)
    sig.split(",").map(&:strip).reject(&:empty?).map do |a|
      [ a.sub(/\Aindexed\s+/, ""), a.start_with?("indexed ") ]
    end
  end

  # { "SilkenCarbonCoin" => { "CarbonMinted" => [[type, indexed], …] } }
  def declared_events
    Dir[REPO_ROOT.join(CONTRACTS_GLOB).to_s].sort.each_with_object({}) do |f, acc|
      File.read(f).scan(EVENT_DECL_RE) do |name, args|
        (acc[File.basename(f, ".sol")] ||= {})[name] = normalize_solidity(args)
      end
    end
  end

  def abi_events(abi_name)
    path = ABI_DIR.join("#{abi_name}.json")
    return nil unless path.exist?

    JSON.parse(path.read).select { |e| e["type"] == "event" }.to_h do |e|
      [ e["name"], e["inputs"].map { |i| [ i["type"], !i["indexed"].nil? && i["indexed"] ] } ]
    end
  end

  # [{ abi:, event:, params: }] — те, що мапінг реально слухає.
  def handled_events
    manifest = YAML.safe_load(MANIFEST.read, aliases: true)
    Array(manifest["dataSources"]).flat_map do |ds|
      mapping = ds["mapping"] || {}
      abi = mapping["abis"]&.first&.fetch("name", nil) || ds.dig("source", "abi")
      Array(mapping["eventHandlers"]).filter_map do |h|
        m = h["event"].to_s.match(/\A([A-Za-z0-9_]+)\((.*)\)\z/m)
        next unless m

        { abi:, event: m[1], params: normalize_graph(m[2]) }
      end
    end
  end
end

RSpec.describe SubgraphAbiParity, type: :quality do
  let(:declared) { described_class.declared_events }
  let(:handled)  { described_class.handled_events }

  # 🔦 Ліхтарі стоять ПЕРШИМИ, бо всі три осі перемагають ПОРОЖНЬОЮ множиною: парсер,
  # що перестав матчити, дав би «нуль розходжень» над нічим (§Guard-craft #61).
  it "витягає непорожню множину ОГОЛОШЕНИХ подій із contracts/*.sol" do
    expect(declared).not_to be_empty
    expect(declared.values.sum(&:size)).to be >= 5
    expect(declared).to include("SilkenCarbonCoin" => hash_including("CarbonMinted"))
  end

  it "витягає непорожню множину ОБРОБЛЮВАНИХ подій із subgraph.yaml" do
    expect(handled.size).to be >= 5
    expect(handled.map { |h| h[:event] }).to include("CarbonMinted", "ParameterUpdated")
    expect(handled.map { |h| h[:abi] }).to all(be_a(String))
  end

  # (1) ABI протух після зміни контракту — найдорожчий напрям, бо `graph build`
  # лишається ЗЕЛЕНИМ над неправильним контрактом.
  it "кожна подія, ОГОЛОШЕНА в contracts/*.sol, має в ABI той самий підпис" do
    mismatches = declared.flat_map do |contract, events|
      abi = described_class.abi_events(contract)
      next [] if abi.nil? # контракт без ABI в субграфі — не його поверхня

      events.filter_map do |name, params|
        next if abi[name] == params

        "#{contract}.#{name}: ABI=#{abi[name].inspect} ⊥ .sol=#{params.inspect}"
      end
    end

    expect(mismatches).to be_empty, "ABI субграфа розійшовся з контрактом:\n  #{mismatches.join("\n  ")}"
  end

  # (2) мапінг слухає подію, якої в названому ним ABI немає — або з іншим підписом.
  it "кожна ОБРОБЛЮВАНА подія існує в ABI, який мапінг для неї називає" do
    bad = handled.filter_map do |h|
      abi = described_class.abi_events(h[:abi])
      next "#{h[:abi]}: ABI-файла немає (subgraph.yaml називає його для #{h[:event]})" if abi.nil?
      next "#{h[:abi]}.#{h[:event]}: обробник є, події в ABI НЕМАЄ" unless abi.key?(h[:event])
      next if abi[h[:event]] == h[:params]

      "#{h[:abi]}.#{h[:event]}: обробник=#{h[:params].inspect} ⊥ ABI=#{abi[h[:event]].inspect}"
    end

    expect(bad).to be_empty, "мапінг ⊥ ABI:\n  #{bad.join("\n  ")}"
  end

  # (3) мапінг слухає подію, якої наш контракт більше не емітує (перейменували/зняли).
  it "кожна ОБРОБЛЮВАНА подія оголошена в нашому Solidity" do
    orphans = handled.reject { |h| declared.dig(h[:abi], h[:event]) }
                     .map { |h| "#{h[:abi]}.#{h[:event]}: обробник є, оголошення в contracts/*.sol НЕМАЄ" }

    expect(orphans).to be_empty, orphans.join("\n  ")
  end
end
