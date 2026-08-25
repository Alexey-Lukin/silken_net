# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe MaintenanceRecord, type: :model do
  before do
    allow(EcosystemHealingWorker).to receive(:perform_async)
  end

  # =========================================================================
  # ASSOCIATIONS
  # =========================================================================
  describe "associations" do
    it "belongs to user" do
      assoc = described_class.reflect_on_association(:user)
      expect(assoc.macro).to eq(:belongs_to)
    end

    it "belongs to maintainable (polymorphic)" do
      assoc = described_class.reflect_on_association(:maintainable)
      expect(assoc.macro).to eq(:belongs_to)
      expect(assoc.options[:polymorphic]).to be true
    end

    it "belongs to ews_alert (optional)" do
      assoc = described_class.reflect_on_association(:ews_alert)
      expect(assoc.macro).to eq(:belongs_to)
      expect(assoc.options[:optional]).to be true
    end

    it "has many attached photos" do
      expect(described_class.new).to respond_to(:photos)
    end
  end

  # =========================================================================
  # ENUMS
  # =========================================================================
  describe "enums" do
    it "defines all action_type values with prefix" do
      record = build(:maintenance_record)
      expect(record).to respond_to(:action_type_installation?)
      expect(record).to respond_to(:action_type_inspection?)
      expect(record).to respond_to(:action_type_cleaning?)
      expect(record).to respond_to(:action_type_repair?)
      expect(record).to respond_to(:action_type_decommissioning?)
      expect(record).to respond_to(:action_type_biomass_extraction?)
    end
  end

  # [PERF.1(д)] Гардовані переходи Puro-анкера (прецедент EthereumAnchor):
  # with_lock + status-гард = перехід рівно-раз; false = програна гонка, не помилка.
  describe "biomass passport lifecycle transitions" do
    let(:record) do
      create(:maintenance_record, :biomass_extraction, :with_evidence,
             maintainable: create(:tree, status: :deceased),
             biomass_passport_tx_hash: "0x#{"ab" * 32}", biomass_passport_status: :sent)
    end

    it "confirms from :sent and refuses a second confirm (race loser gets false)" do
      expect(record.confirm_biomass_passport!).to be(true)
      expect(record.reload).to be_biomass_passport_confirmed
      expect(record.confirm_biomass_passport!).to be(false)
    end

    it "allows confirm/fail from :manual_review (guarded operator exit after console-звірки)" do
      record.update!(biomass_passport_status: :manual_review)

      expect(record.confirm_biomass_passport!).to be(true)
    end

    it "escalates only from :sent — a terminal :failed anchor is not re-escalated" do
      record.update!(biomass_passport_status: :failed)

      expect(record.escalate_biomass_passport!).to be(false)
      expect(record.reload).to be_biomass_passport_failed
    end

    it "never resurrects a terminal :confirmed anchor via fail!" do
      record.update!(biomass_passport_status: :confirmed)

      expect(record.fail_biomass_passport!).to be(false)
      expect(record.reload).to be_biomass_passport_confirmed
    end
  end

  # =========================================================================
  # VALIDATIONS — базові
  # =========================================================================
  # [SEC.27] Найстаріше вкладення дерева і єдине, чия валідація роками не мала
  # поведінкового піна: `spec/quality/attachment_validation_discipline_spec.rb`
  # стереже, що декларація ІСНУЄ, і структурно сліпий до того, чи вона працює.
  # Тут — доказова база Evidence Protocol, тож пара «проходить ⊥ відпадає»
  # коштує дешевше за будь-який інший пін цієї родини.
  describe "photos attachment validation" do
    let(:record) { create(:maintenance_record) }

    def attach_photo(content_type:, bytes: "x")
      record.photos.attach(
        io: StringIO.new(bytes), filename: "evidence", content_type: content_type
      )
    end

    it "accepts the field-photo formats a phone produces" do
      attach_photo(content_type: "image/heic")
      expect(record).to be_valid
    end

    it "rejects a content type outside the allow-list" do
      attach_photo(content_type: "application/pdf")
      expect(record).not_to be_valid
      expect(record.errors[:photos]).to be_present
    end

    it "rejects a photo over the size ceiling" do
      attach_photo(content_type: "image/jpeg", bytes: "x" * 21.megabytes)
      expect(record).not_to be_valid
    end

    it "caps the number of photos per record" do
      11.times { attach_photo(content_type: "image/jpeg") }
      expect(record).not_to be_valid
      expect(record.errors[:photos]).to be_present
    end
  end

  describe "validations" do
    it "is valid with default factory" do
      expect(build(:maintenance_record)).to be_valid
    end

    it "requires action_type" do
      expect(build(:maintenance_record, action_type: nil)).not_to be_valid
    end

    it "requires performed_at" do
      expect(build(:maintenance_record, performed_at: nil)).not_to be_valid
    end

    it "requires notes" do
      expect(build(:maintenance_record, notes: nil)).not_to be_valid
    end

    it "requires notes to be at least 10 characters" do
      expect(build(:maintenance_record, notes: "Short")).not_to be_valid
    end

    it "rejects performed_at in the future" do
      expect(build(:maintenance_record, performed_at: 1.hour.from_now)).not_to be_valid
    end

    # -----------------------------------------------------------------------
    # OpEx Financial Tracking (Series C)
    # -----------------------------------------------------------------------
    describe "labor_hours" do
      it "allows nil" do
        expect(build(:maintenance_record, labor_hours: nil)).to be_valid
      end

      it "allows zero" do
        expect(build(:maintenance_record, labor_hours: 0)).to be_valid
      end

      it "allows positive value" do
        expect(build(:maintenance_record, labor_hours: 3.5)).to be_valid
      end

      it "rejects negative value" do
        record = build(:maintenance_record, labor_hours: -1)
        expect(record).not_to be_valid
        expect(record.errors[:labor_hours]).to be_present
      end
    end

    describe "parts_cost" do
      it "allows nil" do
        expect(build(:maintenance_record, parts_cost: nil)).to be_valid
      end

      it "allows zero" do
        expect(build(:maintenance_record, parts_cost: 0)).to be_valid
      end

      it "allows positive value" do
        expect(build(:maintenance_record, parts_cost: 250.50)).to be_valid
      end

      it "rejects negative value" do
        record = build(:maintenance_record, parts_cost: -10)
        expect(record).not_to be_valid
        expect(record.errors[:parts_cost]).to be_present
      end
    end

    # -----------------------------------------------------------------------
    # Hardware State Sync
    # -----------------------------------------------------------------------
    describe "hardware_verified" do
      it "defaults to false" do
        expect(described_class.new.hardware_verified).to be false
      end

      it "accepts true" do
        expect(build(:maintenance_record, :hardware_verified)).to be_valid
      end
    end

    # -----------------------------------------------------------------------
    # Afterlife Economy: biomass_yield_kg (Puro.earth D-MRV)
    # -----------------------------------------------------------------------
    describe "biomass_yield_kg" do
      it "is required for biomass_extraction" do
        record = build(:maintenance_record, action_type: :biomass_extraction,
                       notes: "Extracted dead wood for Biochar.",
                       biomass_yield_kg: nil)
        expect(record).not_to be_valid
        expect(record.errors[:biomass_yield_kg]).to be_present
      end

      it "must be greater than 0 for biomass_extraction" do
        record = build(:maintenance_record, action_type: :biomass_extraction,
                       notes: "Extracted dead wood for Biochar.",
                       biomass_yield_kg: 0)
        expect(record).not_to be_valid
        expect(record.errors[:biomass_yield_kg]).to be_present
      end

      it "accepts positive value for biomass_extraction" do
        expect(build(:maintenance_record, :biomass_extraction, :with_evidence)).to be_valid
      end

      it "does not require biomass_yield_kg for other action types" do
        expect(build(:maintenance_record, action_type: :inspection, biomass_yield_kg: nil)).to be_valid
      end
    end

    # -----------------------------------------------------------------------
    # GPS Coordinates (anti-sofa-repair)
    # -----------------------------------------------------------------------
    describe "coordinates" do
      it "allows nil latitude and longitude" do
        expect(build(:maintenance_record, latitude: nil, longitude: nil)).to be_valid
      end

      it "is valid with GPS coordinates" do
        expect(build(:maintenance_record, :with_gps)).to be_valid
      end

      it "rejects latitude out of range" do
        record = build(:maintenance_record, latitude: 100.0, longitude: 32.0)
        expect(record).not_to be_valid
        expect(record.errors[:latitude]).to be_present
      end

      it "rejects longitude out of range" do
        record = build(:maintenance_record, latitude: 49.0, longitude: 200.0)
        expect(record).not_to be_valid
        expect(record.errors[:longitude]).to be_present
      end
    end

    # -----------------------------------------------------------------------
    # Evidence Protocol (Trust Protocol)
    # -----------------------------------------------------------------------
    describe "photos required for repair and installation" do
      it "is invalid for :repair without photos" do
        record = build(:maintenance_record, :repair)
        expect(record).not_to be_valid
        expect(record.errors[:photos]).to include(
          a_string_matching(/required for 'repair' and 'installation'/)
        )
      end

      it "is invalid for :installation without photos" do
        record = build(:maintenance_record, :installation)
        expect(record).not_to be_valid
        expect(record.errors[:photos]).to include(
          a_string_matching(/required for 'repair' and 'installation'/)
        )
      end

      it "does NOT require photos for :inspection" do
        expect(build(:maintenance_record, action_type: :inspection)).to be_valid
      end

      it "does NOT require photos for :cleaning" do
        expect(build(:maintenance_record, action_type: :cleaning)).to be_valid
      end

      it "does NOT require photos for :decommissioning" do
        expect(build(:maintenance_record, action_type: :decommissioning)).to be_valid
      end

      # 🔴 [E.20, ⚖️ founder 2026-08-24] Пін ПЕРЕВЕРНУТО: доти цей приклад стверджував,
      # що biomass фото НЕ вимагає, і саме на цьому трималась заявка-самозвіт. Тепер
      # доказ вимагається від дверей — заявка на вилучення біомаси незворотно виходить
      # у ЗОВНІШНІЙ реєстр (Puro.earth CORC).
      it "DOES require a photo for :biomass_extraction (claim leaves for an external registry)" do
        record = build(:maintenance_record, :biomass_extraction)

        expect(record).not_to be_valid
        expect(record.errors[:photos]).to be_present
        expect(build(:maintenance_record, :biomass_extraction, :with_evidence)).to be_valid
      end

      # 🔴 Другі двері, і саме вони визначили ФОРМУ гейта: `on: :create` лишав би
      # обхід «створити як inspection → перевести в biomass».
      # ⚠️ Цей коментар доти обґрунтовував модельне розміщення піна тим, що через
      # HTTP переведення падає РАНІШЕ — на `biomass_yield_kg`, якого немає в
      # permit-списку. Ця підстава померла разом із додаванням писача (E.20,
      # 2026-08-25): поле пермітиться, тож HTTP-двері реальні. Пін лишається тут
      # (модель — дім інваріанта), а дзеркальний request-приклад стереже, що
      # двері закриті САМЕ на цій валідації, а не збігом іншої.
      it "refuses a photo-less record being FLIPPED into :biomass_extraction" do
        record = create(:maintenance_record, action_type: :inspection)

        expect(record.update(action_type: :biomass_extraction, biomass_yield_kg: 42.0)).to be false
        expect(record.errors[:photos]).to be_present
        expect(record.reload.action_type).to eq("inspection")
      end

      # ⛔ Дзеркало сусіда з ПРОТИЛЕЖНИМ знаком: `system_generated` звільняє від
      # Evidence Protocol (у платформи немає камери) — і саме тому платформа НЕ МОЖЕ
      # подати заявку, що виходить у зовнішній реєстр. Скопійований сюди виняток був
      # би дірою з виглядом однорідності.
      it "refuses a biomass claim even from a system-generated record (the platform has no camera)" do
        record = build(:maintenance_record, :biomass_extraction, system_generated: true)

        expect(record).not_to be_valid
        expect(record.errors[:photos]).to be_present
      end

      # Дзеркало: пізніші `update!` (їх роблять ОБИДВА Puro-воркери) типу не міняють,
      # тож валідація на них мовчить — інакше паспорт завис би в `:sent` назавжди.
      it "stays silent on later updates that do not touch action_type" do
        record = create(:maintenance_record, :biomass_extraction, :with_evidence)
        record.photos.purge

        expect(record.reload.update(biomass_passport_status: :sent)).to be true
      end

      # [ARCH.91] Виняток мусить пережити reload: валідація біжить на кожен
      # `save`, тож ознака, що живе лише в інстансі, робить системний запис
      # невиправно невалідним — і `verify` разом з нею.
      context "when the record is system-generated" do
        it "does NOT require photos" do
          expect(build(:maintenance_record, :installation, system_generated: true)).to be_valid
        end

        it "stays updatable after crossing the persistence boundary" do
          record = create(:maintenance_record, :installation, system_generated: true)

          reloaded = described_class.find(record.id)
          expect(reloaded.system_generated).to be true
          expect(reloaded).to be_valid
          expect(reloaded.update(hardware_verified: true)).to be true
          expect(described_class.find(record.id).update(notes: "Corrected installation note")).to be true
        end
      end
    end
  end

  # =========================================================================
  # SCOPES
  # =========================================================================
  describe "scopes" do
    describe ".recent" do
      it "orders by performed_at descending" do
        old_record = create(:maintenance_record, performed_at: 2.days.ago)
        new_record = create(:maintenance_record, performed_at: 1.hour.ago)

        expect(described_class.recent.first).to eq(new_record)
        expect(described_class.recent.last).to eq(old_record)
      end
    end

    describe ".by_type" do
      it "filters by action_type" do
        inspection     = create(:maintenance_record, performed_at: 3.hours.ago)
        cleaning_record = create(:maintenance_record, action_type: :cleaning,
                                                      notes: "Cleaned solar panels on node carefully.")

        expect(described_class.by_type(:inspection)).to include(inspection)
        expect(described_class.by_type(:cleaning)).to include(cleaning_record)
        expect(described_class.by_type(:inspection)).not_to include(cleaning_record)
      end
    end

    describe ".hardware_verified" do
      it "returns only hardware_verified records" do
        verified   = create(:maintenance_record, :hardware_verified)
        unverified = create(:maintenance_record, hardware_verified: false)

        results = described_class.hardware_verified
        expect(results).to include(verified)
        expect(results).not_to include(unverified)
      end
    end

    describe ".with_gps" do
      it "returns only records with GPS coordinates" do
        with_gps    = create(:maintenance_record, :with_gps)
        without_gps = create(:maintenance_record)

        expect(described_class.with_gps).to include(with_gps)
        expect(described_class.with_gps).not_to include(without_gps)
      end

      # 🔦 Дзеркало ліхтаря з `tree_spec` — обидві фікстури вище мають або
      # обидві координати, або жодної, тож зламану (АБО-) форму скоупа вони
      # пропускають. Тут це не гігієна: `with_gps` — доказова поверхня
      # Anti-Sofa-Repair, і «є GPS» з однією координатою є хибним свідченням.
      it "excludes a record that has only one coordinate" do
        half_lat = create(:maintenance_record, latitude: 49.4, longitude: nil)
        half_lng = create(:maintenance_record, latitude: nil, longitude: 32.0)

        expect(described_class.with_gps).not_to include(half_lat)
        expect(described_class.with_gps).not_to include(half_lng)
      end
    end
  end

  # =========================================================================
  # METHODS
  # =========================================================================
  # 🔴 [ARCH.103] Три приклади цього блоку доти ЦЕМЕНТУВАЛИ фабрикацію, і два з них
  # зізнавались у власній назві («returns 0.0 when … are nil», «returns only
  # parts_cost when labor_hours is nil»). Тобто сюїта вимагала, щоб «не введено»
  # рахувалось нулем — і поки вона цього вимагала, дефект був не багом, а контрактом.
  describe "#total_cost" do
    it "is nil when neither cost input was entered" do
      record = build(:maintenance_record, labor_hours: nil, parts_cost: nil)
      expect(record.total_cost).to be_nil
    end

    # ⚠️ Пара несуча саме РАЗОМ: перший приклад доводить, що порожнє поле не стає
    # нулем, другий — що ВВЕДЕНИЙ нуль лишається виміром. Без другого найдешевший
    # спосіб «полагодити» перший — глушити будь-який нуль, і тоді безкоштовний
    # візит став би невидимим.
    it "is nil when only one input was entered — a Total may not hide an unknown addend" do
      record = build(:maintenance_record, labor_hours: 2.0, parts_cost: nil)
      expect(record.total_cost).to be_nil

      record = build(:maintenance_record, labor_hours: nil, parts_cost: 150.0)
      expect(record.total_cost).to be_nil
    end

    it "is a real 0.0 when both inputs were entered as zero (a free visit is a measurement)" do
      record = build(:maintenance_record, labor_hours: 0, parts_cost: 0)
      expect(record.total_cost).to eq(0.0)
    end

    it "adds parts_cost to labor cost" do
      record = build(:maintenance_record, labor_hours: 1.0, parts_cost: 300.0)
      expected = (1.0 * MaintenanceRecord::LABOR_RATE_PER_HOUR) + 300.0
      expect(record.total_cost).to eq(expected)
    end
  end

  # =========================================================================
  # CALLBACKS
  # =========================================================================
  describe "callbacks" do
    it "triggers EcosystemHealingWorker after create" do
      create(:maintenance_record)

      expect(EcosystemHealingWorker).to have_received(:perform_async).with(kind_of(Integer))
    end
  end

  # =========================================================================
  # FACTORY
  # =========================================================================
  describe "factory" do
    it "creates a valid default record" do
      expect(build(:maintenance_record)).to be_valid
    end

    it "creates a valid record with GPS and cost" do
      expect(build(:maintenance_record, :with_gps, :with_cost)).to be_valid
    end

    it "creates a valid hardware_verified record" do
      expect(build(:maintenance_record, :hardware_verified)).to be_valid
    end
  end

  # [UI.6] Дім правила «хто може мутувати запис». Доти воно жило приватним методом
  # контролера — тож ані UI, ані вкладений photos-контролер його не бачили, і обидва
  # через це його не мали. Тут пінимо саму ФОРМУЛУ; що компонент її слухається —
  # `spec/views`, що актор доїжджає з контролера — request-спеки.
  describe "#mutable_by?" do
    let(:organization) { create(:organization) }
    let(:author) { create(:user, :forester, organization: organization) }
    let(:record) { create(:maintenance_record, user: author) }

    it "дозволяє авторові" do
      expect(record.mutable_by?(author)).to be(true)
    end

    it "відмовляє іншому форестеру тієї ж організації" do
      other = create(:user, :forester, organization: organization)

      expect(record.mutable_by?(other)).to be(false)
    end

    it "дозволяє admin+ як override для аудиту" do
      admin = create(:user, :admin, organization: organization)

      expect(record.mutable_by?(admin)).to be(true)
    end

    it "відмовляє без актора (fail-closed)" do
      expect(record.mutable_by?(nil)).to be(false)
    end

    # ⚠️ Свідома межа предиката, а не прогалина: приналежність тримає асоціативний скоуп
    # у викликача (`acting_organization!.clusters` → `set_record`), тобто чужий запис до
    # предиката просто не доїжджає. Пін фіксує КОНТРАКТ — хто кличе цей метод, той
    # зобовʼязаний був дістати запис org-скоупленим запитом.
    it "про організацію не питає — це обовʼязок викликача" do
      foreign_admin = create(:user, :admin, organization: create(:organization))

      expect(record.mutable_by?(foreign_admin)).to be(true)
    end
  end

  # [UI.4] Третій продюсер стрічки подій дашборда. Дзеркало
  # `BlockchainTransaction#broadcast_ledger_signal` — і форма піна та сама, бо
  # клас дефекту той самий: механізм на місці, пускач наполовину мертвий, мовчить
  # усе, крім екрана.
  describe "broadcast_maintenance_signal" do
    before { allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to) }

    def maintenance_stream_for(organization)
      "maintenance_records_org_#{organization.id}_e#{organization.stream_epoch}"
    end

    # ⚠️ Організація АВТОРА, не поліморфного `maintainable`: саме так стрічка
    # скоупить обслуговування (`where(users: { organization_id: org.id })`). Дерево
    # тут навмисне з ЧУЖОГО кластера — інакше приклад був би зелений і тоді, коли
    # сигнал іде хибним шляхом, бо обидві організації збігалися б.
    it "signals the organization of the record's AUTHOR, not of the maintainable" do
      author = create(:user)
      foreign_tree = create(:tree, cluster: create(:cluster, organization: create(:organization)))

      create(:maintenance_record, user: author, maintainable: foreign_tree)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to)
        .with(maintenance_stream_for(author.organization))
    end

    # Поява й зміна — одна реєстрація на дві події (`on: %i[create update]`).
    # Дві окремі реєстрації з тим самим іменем фільтра дали б ОДИН колбек з
    # опціями останньої, і половина пускача померла б тихо.
    it "signals again when the record is edited" do
      record = create(:maintenance_record)

      record.update!(notes: "Follow-up inspection after the storm.")

      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to)
        .with(maintenance_stream_for(record.user.organization)).at_least(:twice)
    end

    # `users.organization_id` nullable (платформений адмін створюється без орг.),
    # тож гілка досяжна. `TurboStreams::Name.org` на `nil` кинув би `ArgumentError`,
    # який власний `rescue` зʼїв би у WARN — гард робить цю тишу СВІДОМОЮ.
    it "stays silent, and raises nothing, when the author has no organization" do
      record = build(:maintenance_record, user: build(:user, organization: nil))

      expect { record.send(:broadcast_maintenance_signal) }.not_to raise_error
      expect(Turbo::StreamsChannel).not_to have_received(:broadcast_refresh_later_to)
    end

    # 🔴 Ціна тут не транзакція, а РОБОТА 👤-оператора в полі: `commit_records` має
    # `ensure` без `rescue`, тож виняток UI-декорації пролетів би нагору з `create!`
    # і вбив подання запису обслуговування заради оновлення чужого екрана.
    it "never lets a signal failure kill the field operator's submission" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to).and_raise(StandardError, "cable down")
      allow(Rails.logger).to receive(:warn)

      expect { create(:maintenance_record) }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/broadcast_maintenance_signal/)
    end
  end

  # [UI.7, ⚖️ 2026-08-20] Дім критерію «залізо підтвердило обслуговування»:
  # пульс вузла ПІСЛЯ performed_at — єдиний канал, якого технік не контролює.
  # Межа несуча в ОБИДВА боки: пульс ДО не рахується (ефір міг бути до втручання),
  # відсутній пульс — тим паче.
  # =========================================================================
  # [E.20] СТАН ЗАЯВКИ НА CORC — дім питання «де вона зараз і хто ходить далі»
  # =========================================================================
  describe "#biomass_claim_state" do
    let(:organization) { create(:organization) }
    let(:author)   { create(:user, :forester, organization: organization) }
    let(:auditor)  { create(:user, :forester, organization: organization) }
    let(:biomass)  { create(:maintenance_record, :biomass_extraction, :with_evidence, user: author) }

    it "is nil for every non-biomass action type — питання до них не стоїть" do
      expect(create(:maintenance_record, user: author).biomass_claim_state).to be_nil
    end

    it "reports :awaiting_attestation while the second pair of eyes is missing" do
      expect(biomass.biomass_claim_state).to eq(:awaiting_attestation)
    end

    # 🔴 Ядро пункту: `biomass_passport_status` сам по собі на це не відповідає —
    # його `nil` однаковий у двох станах із РІЗНИМИ адресатами (інший лісник ⊥
    # оператор платформи). Саме тому стан є деривацією, а не колонкою.
    it "reports :not_filed when the signature exists but the claim never left" do
      allow(PuroEarthPassportWorker).to receive(:perform_async)
      biomass.attest!(auditor)

      expect(biomass.reload.biomass_passport_status).to be_nil
      expect(biomass.biomass_claim_state).to eq(:not_filed)
    end

    it "surfaces the passport lifecycle once the anchor exists" do
      allow(PuroEarthPassportWorker).to receive(:perform_async)
      biomass.attest!(auditor)
      biomass.update!(biomass_passport_status: :sent, biomass_passport_tx_hash: "0x#{'ab' * 32}")

      expect(biomass.biomass_claim_state).to eq(:sent)
      expect(biomass.confirm_biomass_passport!).to be_truthy
      expect(biomass.biomass_claim_state).to eq(:confirmed)
    end
  end

  describe ".awaiting_attestation" do
    let(:author) { create(:user, :forester) }

    it "collects only unsigned biomass claims" do
      pending_claim = create(:maintenance_record, :biomass_extraction, :with_evidence, user: author)
      signed_claim  = create(:maintenance_record, :biomass_extraction, :with_evidence, :attested, user: author)
      plain         = create(:maintenance_record, user: author)

      ids = described_class.awaiting_attestation.pluck(:id)
      expect(ids).to include(pending_claim.id)
      expect(ids).not_to include(signed_claim.id, plain.id)
    end
  end

  # [E.20] Ратифікована незалежність — акаунт У організації власника + ДОГОВІР.
  # Підпис super_admin рятує орг з одним лісником від глухого кута, але це СЛАБША
  # форма, і поверхня мусить її показувати, а не ховати.
  describe "#attested_outside_owner_organization?" do
    let(:owner_org) { create(:organization) }
    let(:author)    { create(:user, :forester, organization: owner_org) }
    let(:record)    { create(:maintenance_record, user: author) }

    it "is false for an unsigned record" do
      expect(record.attested_outside_owner_organization?).to be false
    end

    it "is false when the attestor lives in the owner organization" do
      record.attest!(create(:user, :forester, organization: owner_org))
      expect(record.reload.attested_outside_owner_organization?).to be false
    end

    it "is true when the platform signs from another organization" do
      record.attest!(create(:user, :super_admin, organization: create(:organization)))
      expect(record.reload.attested_outside_owner_organization?).to be true
    end
  end

  describe "#hardware_pulse_confirmed?" do
    let(:record) { create(:maintenance_record, performed_at: 1.hour.ago) }

    it "confirms when the unit pulsed after the maintenance" do
      record.maintainable.update!(last_seen_at: 10.minutes.ago)
      expect(record.hardware_pulse_confirmed?).to be true
    end

    it "refuses when the last pulse predates the maintenance" do
      record.maintainable.update!(last_seen_at: 2.hours.ago)
      expect(record.hardware_pulse_confirmed?).to be false
    end

    it "refuses when the unit never pulsed at all" do
      record.maintainable.update!(last_seen_at: nil)
      expect(record.hardware_pulse_confirmed?).to be false
    end

    it "refuses when the maintainable is gone (nullified FK on a deleted unit)" do
      record.update_columns(maintainable_id: nil, maintainable_type: nil)
      expect(record.reload.hardware_pulse_confirmed?).to be false
    end

    it "refuses on a record without performed_at (unsaved / insert_all path)" do
      # Гард на blank існує саме тому, що предикат питають і до валідацій.
      expect(described_class.new.hardware_pulse_confirmed?).to be false
    end
  end

  # =========================================================================
  # [E.20] «АТЕСТАТОР ≠ БЕНЕФІЦІАР» — друга пара очей
  # ⚖️ founder 2026-08-24: незалежність тримає ДОГОВІР, а код стереже єдине, що
  # взагалі здатен, — що підписав НЕ той, хто написав.
  # =========================================================================
  describe "#attest!" do
    let(:organization) { create(:organization) }
    let(:author) { create(:user, :forester, organization: organization) }
    let(:auditor) { create(:user, :forester, organization: organization) }
    let(:record) { create(:maintenance_record, user: author) }

    it "records the attestor and the moment" do
      freeze_time do
        expect(record.attest!(auditor)).to be_truthy
        expect(record.reload.attestor).to eq(auditor)
        expect(record.attested_at).to eq(Time.current)
        expect(record).to be_attested
      end
    end

    # 🔴 Ядро присуду: самозвіт — рівно те, проти чого стоїть увесь won't-do
    # гільдії. Без цієї гілки поле лишалось би декорацією.
    it "refuses self-attestation by the record's own author" do
      expect { record.attest!(author) }.to raise_error(described_class::SelfAttestation)
      expect(record.reload).not_to be_attested
    end

    # Дзеркало `EwsAlert#claim!`: повтор не сміє зсувати ЧАС засвідчення — саме
    # штамп робить запис доказом.
    it "is a no-op on re-attestation by the same auditor" do
      record.attest!(auditor)
      original = record.reload.attested_at

      travel 20.minutes do
        expect(record.attest!(auditor)).to be_truthy
        expect(record.reload.attested_at).to eq(original)
      end
    end

    it "reports a fresh record as not attested" do
      expect(record).not_to be_attested
      expect(record.attestor).to be_nil
    end

    # 🔴 [E.20] Підпис — ПУСКАЧ незворотної заявки. Пін несе не зручність, а
    # підставу присуду: доти паспорт ставив у чергу healing-воркер безумовно, тож
    # «вікно для атестатора» фактично дорівнювало життю джоби (≈8 хв до DeadSet).
    it "files the biomass passport claim at the moment of attestation" do
      biomass = create(:maintenance_record, :biomass_extraction, :with_evidence, user: author)
      allow(PuroEarthPassportWorker).to receive(:perform_async)

      biomass.attest!(auditor)

      expect(PuroEarthPassportWorker).to have_received(:perform_async).with(biomass.id)
    end

    it "does not file a claim when the attested record is not a biomass extraction" do
      allow(PuroEarthPassportWorker).to receive(:perform_async)

      record.attest!(auditor)

      expect(PuroEarthPassportWorker).not_to have_received(:perform_async)
    end
  end

  # 🔴 [E.20] Односторонні двері: без них замок доказу знімається одним enum-полем.
  describe "biomass claim is one-way" do
    it "refuses flipping a filed biomass claim back to another action type" do
      record = create(:maintenance_record, :biomass_extraction, :with_evidence)

      expect(record.update(action_type: :inspection)).to be false
      expect(record.errors[:action_type]).to be_present
      expect(record.reload.action_type).to eq("biomass_extraction")
    end

    # Дзеркало: інші типи лишаються редагованими — правило вузьке за наміром.
    it "still allows correcting a non-biomass action type" do
      record = create(:maintenance_record, action_type: :inspection)

      expect(record.update(action_type: :cleaning)).to be true
    end
  end
end
