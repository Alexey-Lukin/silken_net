# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SilkenNet::Attractor do
  # [SEC.11] Post-cutover the attractor takes initial (x₀, y₀, z₀)
  # directly — no `chaos_seed`, no DID-as-seed shortcut. The little
  # `xyz_for(seed)` helper is just a deterministic generator for test
  # input fixtures (mirrors firmware/test/test_bio_contract.c
  # `seed_to_xyz`); production code feeds (x₀, y₀, z₀) derived from
  # K_seed via SilkenNet::SeedDerivation.
  def xyz_for(seed)
    [
      ((seed % 1000) / 500.0) - 1.0,
      (((seed >> 4) % 1000) / 500.0) - 1.0,
      (((seed >> 8) % 1000) / 500.0) - 1.0
    ]
  end

  def calc_z(seed, temp, acoustic, dt = 60, vcap = 3300)
    x, y, z = xyz_for(seed)
    described_class.calculate_z_from_state(x, y, z, temp, acoustic, dt, vcap).first
  end

  describe ".calculate_z_from_state" do
    it "returns [z_rounded, x_final, y_final, z_final] of finite Floats" do
      result = described_class.calculate_z_from_state(0.1, 0.2, 0.3, 20.0, 5)
      expect(result).to be_an(Array)
      expect(result.size).to eq(4)
      expect(result).to all(be_a(Float).and(be_finite))
    end

    it "is deterministic for identical inputs" do
      a = described_class.calculate_z_from_state(0.42, -0.17, 0.31, 18.5, 4, 55, 3290)
      b = described_class.calculate_z_from_state(0.42, -0.17, 0.31, 18.5, 4, 55, 3290)
      expect(a).to eq(b)
    end

    it "still computes when SilkenNet::Metrics is undefined (defined?-guarded observe)" do
      hide_const("SilkenNet::Metrics")
      result = described_class.calculate_z_from_state(0.1, 0.2, 0.3, 20.0, 5)
      expect(result).to all(be_a(Float).and(be_finite))
    end

    it "is sensitive to the initial state — different x₀ → different Z" do
      a = described_class.calculate_z_from_state(0.1, 0.2, 0.3, 20.0, 5)
      b = described_class.calculate_z_from_state(0.9, 0.2, 0.3, 20.0, 5)
      expect(a.first).not_to eq(b.first)
    end

    it "is sensitive to temperature" do
      a = calc_z(42, 10.0, 5)
      b = calc_z(42, 50.0, 5)
      expect(a).not_to eq(b)
    end

    it "[E.63] is INDEPENDENT of delta_t/vcap — metabolism no longer perturbs β/Z" do
      # Lorenz is now a pure chaos gate (β = BASE_BETA). Metabolism sets
      # growth_points directly on-device (firmware BioContract), so Z must
      # NOT move with delta_t/vcap — decoupled. 00_07 E.63.
      base = described_class.calculate_z_from_state(0.1, 0.2, 0.3, 20.0, 5, 60, 3300)
      fast = described_class.calculate_z_from_state(0.1, 0.2, 0.3, 20.0, 5, 10, 3500)
      slow = described_class.calculate_z_from_state(0.1, 0.2, 0.3, 20.0, 5, 7200, 2800)
      expect(fast.first).to eq(base.first)
      expect(slow.first).to eq(base.first)
    end

    it "stays finite under extreme inputs" do
      results = [
        described_class.calculate_z_from_state(0.0, 0.0, 0.0, 200.0, 5),
        described_class.calculate_z_from_state(0.0, 0.0, 0.0, 22.0, 500),
        described_class.calculate_z_from_state(0.0, 0.0, 0.0, 25.0, 10, 0, 65_535),
        described_class.calculate_z_from_state(-1.0, -1.0, -1.0, -40.0, 0)
      ]
      expect(results.flatten).to all(be_finite)
    end
  end

  describe ".homeostatic? [E.64 ρ-relative anomaly ceiling]" do
    let(:family) { build(:tree_family, critical_z_min: 5.0, critical_z_max: 45.0) }

    it "returns true when z within bounds (temp=0 → ρ=28 → ceiling=45)" do
      expect(described_class.homeostatic?(25.0, family, 0.0)).to be true
    end

    it "returns false below critical_z_min (absolute stress floor)" do
      expect(described_class.homeostatic?(3.0, family, 0.0)).to be false
    end

    it "returns false above the ρ-relative anomaly ceiling (temp=0 → 45)" do
      expect(described_class.homeostatic?(50.0, family, 0.0)).to be false
    end

    it "returns true at boundary values (inclusive, temp=0)" do
      expect(described_class.homeostatic?(5.0, family, 0.0)).to be true
      expect(described_class.homeostatic?(45.0, family, 0.0)).to be true
    end

    it "[E.64] warm temp raises the ceiling — z=50 anomaly@temp=0, homeostatic@temp=60" do
      # temp=60 → ρ=40 → ceiling = 40 + (45-28) = 57; z=50 < 57 → homeostatic (not a warm-day false anomaly)
      expect(described_class.homeostatic?(50.0, family, 0.0)).to be false
      expect(described_class.homeostatic?(50.0, family, 60.0)).to be true
    end

    it "[E.64] anomaly_ceiling preserves critical_z_max at ρ=BASE_RHO (temp=0)" do
      expect(described_class.anomaly_ceiling(0.0, 45.0)).to be_within(1e-9).of(45.0)
    end
  end

  describe ".generate_trajectory" do
    it "returns ITERATIONS * 3 finite Floats (flat x,y,z stream)" do
      trajectory = described_class.generate_trajectory(0.0, 0.0, 0.0, 22.0, 5)
      expect(trajectory.size).to eq(SilkenNet::Attractor::ITERATIONS * 3)
      expect(trajectory).to all(be_a(Float).and(be_finite))
    end

    it "is deterministic for identical inputs" do
      a = described_class.generate_trajectory(0.1, 0.2, 0.3, 22.0, 5)
      b = described_class.generate_trajectory(0.1, 0.2, 0.3, 22.0, 5)
      expect(a).to eq(b)
    end
  end

  describe "constants" do
    it "exposes Float-only base constants (firmware mruby parity)" do
      expect(SilkenNet::Attractor::BASE_SIGMA).to be_a(Float)
      expect(SilkenNet::Attractor::BASE_RHO).to be_a(Float)
      expect(SilkenNet::Attractor::BASE_BETA).to be_a(Float)
    end

    it "BASE_BETA == IEEE-754 8.0/3.0 (bit-identical to firmware)" do
      expect(SilkenNet::Attractor::BASE_BETA).to eq(8.0 / 3.0)
    end

    it "DT == 0.01 and ITERATIONS == 250" do
      expect(SilkenNet::Attractor::DT).to eq(0.01)
      expect(SilkenNet::Attractor::ITERATIONS).to eq(250)
    end

    it "exposes σ/ρ Range clamps" do
      expect(SilkenNet::Attractor::SIGMA_LIMITS).to be_a(Range)
      expect(SilkenNet::Attractor::RHO_LIMITS).to be_a(Range)
    end
  end

  # [E.64] Дзеркало пакування — три гілки прямо, бо 200-кейсовий fuzz нижче їх НЕ
  # покриває рівномірно за побудовою: `stress` (z < 2) на реальному cold-start не
  # трапляється практично ніколи (ρ-clamp тримає z_eq ≥ 9 — 03_04 §4), а anomaly
  # рідкісна за дизайном [E.64]. Тобто fuzz доводить ЗБІГ із прошивкою там, куди
  # долітає, а ці приклади доводять, що решта гілок узагалі жива.
  describe ".pack_status_byte" do
    def unpack(byte) = [ (byte >> 5) & 0x03, byte & 0x1F ]

    it "stress: нижче абсолютної підлоги → status 1, GP рівно 1" do
      byte = described_class.pack_status_byte(1.5, 20, 1800, critical_z_min: 2.0, critical_z_max: 45.0)
      expect(unpack(byte)).to eq([ 1, described_class::GP_STRESS ])
    end

    it "anomaly: вище ρ-ВІДНОСНОЇ стелі → status 2, емісія нуль" do
      # ceiling(20 °C) = ρ(32) + (45 − 28) = 49 → 60 поза нею.
      byte = described_class.pack_status_byte(60.0, 20, 1800, critical_z_min: 2.0, critical_z_max: 45.0)
      expect(unpack(byte)).to eq([ 2, 0 ])
    end

    it "homeostasis: GP бере метаболізм, а не Z" do
      byte = described_class.pack_status_byte(31.0, 20, described_class::DELTA_T_SLOW_S,
                                              critical_z_min: 2.0, critical_z_max: 45.0)
      expect(unpack(byte)).to eq([ 0, described_class::GP_HOMEO_MIN ])
    end

    # 🔴 [ARCH.102] Оголошений регістр «я тут, але не міряв»: гомеостаз ВИМІРЯНО
    # (Лоренц-гейт відпрацював), метаболізм — ні. Пара `status 0 / GP 0` мусить
    # пережити дзеркало, інакше DCI оголосила б розходженням чесну відмову вузла.
    it "сентинел: метаболізм не виміряно → status 0, GP 0 (а НЕ гомеостаз-мінімум)" do
      byte = described_class.pack_status_byte(31.0, 20, described_class::DELTA_T_UNKNOWN_S,
                                              critical_z_min: 2.0, critical_z_max: 45.0)
      expect(unpack(byte)).to eq([ 0, described_class::GP_UNMEASURED ])
    end

    # ⊥ Ліхтар: ρ-відносність не є декорацією. На теплому дні та сама Z лишається
    # гомеостазом — саме цей фікс [E.64] прибрав хибну аномалію від ambient-temp.
    it "та сама Z на теплому дні лишається гомеостазом (ρ-відносна стеля)" do
      cold = described_class.pack_status_byte(47.0, -10, 1800, critical_z_min: 2.0, critical_z_max: 45.0)
      warm = described_class.pack_status_byte(47.0, 40, 1800, critical_z_min: 2.0, critical_z_max: 45.0)

      expect(unpack(cold).first).to eq(2)
      expect(unpack(warm).first).to eq(0)
    end
  end

  describe "Dual Computation Integrity (REAL firmware contract — subprocess)" do
    # [FW.57 F4] The firmware contract (firmware/bio_contracts/bio_contract.rb)
    # defines its OWN SilkenNet::Attractor, so it can't be co-loaded with the
    # backend in one process. We run it in an isolated subprocess and compare its
    # output DIRECTLY to the backend mirror — replacing the old hand-copied
    # `firmware_z` (a 3rd kernel copy that could silently drift while both
    # "parity" sides still agreed). Z + the FULL StatusByte are compared.
    # 🔴 [2026-09-06] Доти тут стояло «GP parity needs a backend metabolic_health
    # mirror (= B, deferred to FW.2)» — і ця підстава ВЖЕ БУЛА МЕРТВА: дзеркало
    # `expected_homeostasis_gp` приїхало з E.63 (г) wire-rev2.1, тобто відкладення
    # пережило власний мотив. Тепер порівнюється весь байт (status ⊕ GP), а не
    # самі лише біти 6..5 — сама причина, з якої `bin/forest_simulator` роками
    # вгадував `bio_status` замість рахувати (00_07 E.64).
    # NB: anomaly (z > ρ-relative ceiling) is rare by design (E.64) → the sweep
    # mostly exercises the homeostasis branch + the kernel Z parity.
    def run_firmware_contract(cases)
      runner = Rails.root.join("tools/firmware/contract_runner.rb").to_s
      out = IO.popen([ Gem.ruby, runner ], "r+") do |io|
        io.write(JSON.generate(cases: cases))
        io.close_write
        io.read
      end
      raise "contract_runner.rb failed (status #{$?.exitstatus}): #{out}" unless $?.success?
      JSON.parse(out)
    end

    # [E.64] ПОВНИЙ байт — status ⊕ growth_points разом. Класифікацію прошивка робить
    # із СИРОГО z (`calculate_z_axis` → `[z, x, y, z]`, без round), тож дзеркало
    # годується `[3]`, а не `[0]`.
    def mirrored_status_byte(be_z, temp, delta_t, fw_family)
      SilkenNet::Attractor.pack_status_byte(
        be_z, temp, delta_t,
        critical_z_min: fw_family.critical_z_min,
        critical_z_max: fw_family.critical_z_max
      )
    end

    # ⛔ ОГОЛОШЕНА СТЕЛЯ [ARCH.8, 2026-09-09; переміряно 2026-09-20]: межа
    # береться СИМВОЛЬНО (`DELTA_T_SLOW_S`), тож діапазон поїде за константою,
    # якщо її рухне біологічна калібрація E.63 — і лише вона: підняти її заради
    # бюджету радіо (важіль (а) ARCH.8) відхилено ⚖️ 2026-09-22 (03_04 §4.3).
    # 🔴 Але САТУРОВАНИЙ режим (`m = 0`, тобто `delta_t > DELTA_T_SLOW_S`) цей
    # фазз не пінує НІКОЛИ — і підняття константи цього не змінить: верхня межа
    # кидка ДОРІВНЮЄ самому порогу (`rand(0..DELTA_T_SLOW_S)`). Тому саторований режим
    # пінує ОКРЕМИЙ детермінований приклад нижче (межа · крок за нею · точка 7884 ·
    # 2× поріг), а не розширений кидок: випадковий діапазон «десь там» дав би
    # ту саму сліпоту до кейса, що не випав.
    # ⊕ Що пінує сам фазз: ЗНАЧЕННЯ підлоги до порогу. На сіді 20_260_502 чотири з 200
    # кейсів дають delta_t >= 7074, де `round(5 + m*26)` сідає на `GP_HOMEO_MIN = 5`.
    # ⚠️ max delta_t = 7161; 7200 при цьому ДОСЯЖНЕ (границя включна, ~2.8 %),
    # просто не випало, а точка 7884 (> порогу) недосяжна ЗА ПОБУДОВОЮ — не плутати
    # «не випало» з «неможливе».
    it "matches the backend Z + bio_status on a 200-case fuzz sweep (real contract, not a mirror)" do
      fw_family = Struct.new(:critical_z_min, :critical_z_max).new(2.0, 45.0)
      rng = Random.new(20_260_502)
      cases = Array.new(200) do
        [ rng.rand(-1.0..1.0), rng.rand(-1.0..1.0), rng.rand(-1.0..1.0),
          rng.rand(-40.0..60.0), rng.rand(0..255), rng.rand(0..described_class::DELTA_T_SLOW_S) ]
      end

      expect_contract_parity(cases, run_firmware_contract(cases), fw_family)
    end

    # 🔴 [ARCH.8] Саторований режим (`m = 0`, `delta_t > DELTA_T_SLOW_S`) — стеля фазза
    # вище: кидок його не дістає ЗА ПОБУДОВОЮ. 7884 с — колишня CCM-точка грошової
    # моделі (до зрізу п'єзо); з 2026-09-29 CCM на моделі стоїть ПЕРЕД підлогою
    # (6512 с, `tx_cadence_budget.rb`), тож кейс лишається як точка глибини сатурації.
    # Кейси детерміновані — межа, крок за нею, 7884, глибока сатурація — і судяться
    # тією самою повною байт-звіркою з реальним контрактом;
    # ⊕ гомеостаз мусить сісти рівно на підлогу `GP_HOMEO_MIN`: пін судить ПІДЛОГУ
    # значенням, а не лише збіг двох сторін. Окремий нижній клемп `m` він не чує — це
    # еквівалентний мутант (підлогу однаково ставить `gp.clamp`), виміряно 2026-09-27.
    it "matches the real contract byte-for-byte in the saturated regime and lands on the GP floor" do
      fw_family = Struct.new(:critical_z_min, :critical_z_max).new(2.0, 45.0)
      slow = described_class::DELTA_T_SLOW_S
      states = [ [ 0.1, -0.2, 0.3, 18.0, 3 ], [ -0.5, 0.4, -0.1, -5.0, 0 ], [ 0.9, 0.9, -0.9, 35.0, 200 ] ]
      cases = [ slow, slow + 1, 7884, 2 * slow ].product(states).map { |dt, (x, y, z, temp, ac)| [ x, y, z, temp, ac, dt ] }

      fw = run_firmware_contract(cases)
      expect_contract_parity(cases, fw, fw_family)

      homeostasis_gp = fw.filter_map { |payload, _| payload & 0x1F if (payload >> 5).nobits?(0x03) }
      expect(homeostasis_gp).not_to be_empty
      expect(homeostasis_gp).to all(eq(described_class::GP_HOMEO_MIN))
    end

    # [FW.8] Смуга, ЧИННА на пристрої, доходить до вердикту: справжній контракт отримує
    # z_min/z_max і мусить судити ТІЄЮ Ж per-species смугою, що й дзеркало. Кейси — лише
    # ті, де родина (5.0/40.0) і дефолти (2.0/45.0) дають РІЗНИЙ статус: на решті обидві
    # сторони збіглися б і без споживання, тобто приклад був би вакуумним. Той самий
    # набір без смуги мусить зійтися з дефолтами — так пін судить СПОЖИВАННЯ, а не лише
    # паритет. ⚠️ C-дзеркало `test_bio_contract.c` цього не бачить за побудовою (гоча #19).
    it "classifies with the per-species band it is handed (FW.8 consumer), not the baked defaults" do
      family = Struct.new(:critical_z_min, :critical_z_max).new(5.0, 40.0)
      defaults = Struct.new(:critical_z_min, :critical_z_max).new(2.0, 45.0)
      rng = Random.new(20_260_927)
      pool = Array.new(3000) do
        [ rng.rand(-1.0..1.0), rng.rand(-1.0..1.0), rng.rand(-1.0..1.0),
          rng.rand(-40.0..60.0), rng.rand(0..255), 1800 ]
      end
      status = lambda do |c, fam|
        z = described_class.calculate_z_from_state(*c)[3]
        mirrored_status_byte(z, c[3], c[5], fam) >> 5
      end
      picked = pool.select { |c| status.(c, family) != status.(c, defaults) }
      expect(picked.map { |c| status.(c, family) }.uniq).to contain_exactly(1, 2)

      banded = picked.map { |c| c + [ family.critical_z_min, family.critical_z_max ] }
      expect_contract_parity(banded, run_firmware_contract(banded), family)
      expect_contract_parity(picked, run_firmware_contract(picked), defaults)
    end

    def expect_contract_parity(cases, fw, fw_family)
      z_div = []
      status_div = []
      byte_div = []

      cases.each_with_index do |(x, y, z, temp, ac, dt), i|
        fw_payload, fw_z = fw[i]
        be_z = described_class.calculate_z_from_state(x, y, z, temp, ac, dt)[3] # raw final Z

        z_div << [ i, fw_z, be_z ] if (fw_z - be_z).abs > 1e-9

        # firmware packs status into bits 6..5; the backend classifies with its
        # REAL homeostatic? / anomaly_ceiling (no hand-copied kernel logic).
        fw_status = (fw_payload >> 5) & 0x03
        agree =
          case fw_status
          when 0 then described_class.homeostatic?(be_z, fw_family, temp)
          when 1 then be_z < fw_family.critical_z_min                                        # stress
          when 2 then be_z > described_class.anomaly_ceiling(temp, fw_family.critical_z_max) # anomaly
          else true # tamper/VM-error not produced by evaluate_and_pack
          end
        status_div << [ i, fw_status, be_z.round(4), temp.round(1) ] unless agree

        be_payload = mirrored_status_byte(be_z, temp, dt, fw_family)
        byte_div << [ i, fw_payload, be_payload, be_z.round(4), temp.round(1), dt ] unless be_payload == fw_payload
      end

      expect(z_div).to be_empty, "Z divergence (real fw ↔ backend): #{z_div.first(3)}"
      expect(status_div).to be_empty, "bio_status divergence (real fw ↔ backend): #{status_div.first(3)}"
      expect(byte_div).to be_empty,
                          "StatusByte divergence (real fw ↔ backend mirror) [i, fw, be, z, temp, dt]: #{byte_div.first(3)}"
    end
  end

  # [ARCH.102] Дзеркало сентинела «метаболізм не виміряно». Дім значення й
  # підстави — `firmware/bio_contracts/bio_contract.rb`; тут доводиться, що
  # DCI-звірка не оголосить розходженням саме чесну відмову пристрою.
  #
  # 🔴 Чому це money-path: доти guard-и wall-time і непрогріта EMA віддавали
  # `BASELINE_DELTA_T_S = 60`, а `metabolic_health(60)` = 1.08 → clamp 1.0 →
  # GP = `GP_HOMEO_MAX`. Тобто відмова виміряти нараховувала МАКСИМУМ балів,
  # які йдуть у `Wallet#credit!` і в `leaf0` тижневого L1-якоря.
  describe ".expected_homeostasis_gp" do
    it "credits nothing when the metabolism was not measured" do
      expect(described_class.expected_homeostasis_gp(described_class::DELTA_T_UNKNOWN_S)).to eq(0)
    end

    # ⊥ Ліхтар: сентинел не сміє зрізати ЖВАВІСТЬ. Виміряні 60 с — це дуже
    # швидкий перезаряд, і він і далі дає максимум; без цієї половини фікс
    # не відрізнити від «просто занизили бали».
    it "still peaks on a genuinely measured fast recharge" do
      expect(described_class.expected_homeostasis_gp(60)).to eq(described_class::GP_HOMEO_MAX)
    end

    it "keeps the measured band between the calibration thresholds" do
      expect(described_class.expected_homeostasis_gp(described_class::DELTA_T_SLOW_S))
        .to eq(described_class::GP_HOMEO_MIN)
    end
  end
end
