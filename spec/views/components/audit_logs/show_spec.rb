# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditLogs::Show do
  def build_user(full_name: "Ada Lovelace", email_address: "ada@silkennet.com", role: "admin")
    # 🔴 [TEST.12] Доти мок оголошував `full_name` І `email_address` як ДВА незалежні
    # поля — а на реальному `User` перше ВИВОДИТЬСЯ з імен і падає на друге
    # (`[first,last].compact_blank.join(" ").presence || email_address`). Тобто зв'язок,
    # який і є суттю цього методу, фікстура розривала, і фолбек «немає імені → показуємо
    # адресу» не перевірявся ніде. Тепер годуємо джерело: імена + адресу.
    first, last = full_name.to_s.split(" ", 2)
    User.new(first_name: first, last_name: last, email_address: email_address, role: role)
  end

  # [TEST.12] `action:` — лише РЕАЛЬНІ значення (12 літералів + 3 `<subj>_to_<state>`-родини
  # + `blockchain_tx_{event}`): доти дефолт «update» був CRUD-стилем, якого цей домен не
  # пише ЖОДНИМ писачем, тож бейдж/заголовок перевірялись входом, недосяжним у проді.
  def build_log(id: 1, action: "system_parameter_changed", auditable_type: "Tree", auditable_id: 42,
               user: nil, metadata: {}, created_at: Time.current)
    AuditLog.new(
      id: id,
      action: action,
      auditable_type: auditable_type,
      auditable_id: auditable_id,
      user: user,
      metadata: metadata,
      created_at: created_at
    )
  end

  let(:user) { build_user }
  let(:log)  { build_log(id: 5, user: user, metadata: { "reason" => "correction" }) }
  let(:html) { render_component(log: log) }

  describe "header section" do
    it "renders Audit Event Record label" do
      expect(html).to include("Audit Event Record")
    end

    # [I18N.1] Свідок у НЕ-базовій локалі: en-мітка `System parameter changed`
    # ПОБАЙТОВО дорівнює humanize, тож англійський пін механізму не бачить —
    # мутація «label → humanize» червонить рівно український приклад.
    it "renders the localized action label as heading (uk)" do
      expect(I18n.with_locale(:uk) { render_component(log: log) })
        .to include("Системний параметр змінено")
    end

    it "renders log id and timestamp" do
      expect(html).to include("#5")
    end
  end

  describe "details table" do
    it "renders Action field" do
      expect(html).to include("Action")
    end

    it "renders Performed By field with user name" do
      expect(html).to include("Ada Lovelace")
    end

    it "renders Target Type field" do
      expect(html).to include("Tree")
    end

    it "renders Target ID field" do
      expect(html).to include("42")
    end
  end

  describe "metadata panel" do
    it "renders Event Metadata heading" do
      expect(html).to include("Event Metadata")
    end

    it "renders metadata key-value pairs" do
      expect(html).to include("reason")
      expect(html).to include("correction")
    end

    it "renders empty metadata notice when no metadata" do
      log_no_meta = build_log(metadata: {})
      html = render_component(log: log_no_meta)
      expect(html).to include("No additional metadata")
    end

    # [I18N.1] `from`/`to` ведуться у свій дім міток: AASM-статуси → `StatusBadge.label`.
    # Локаль НЕ базова: en-мітка «draft» збігається з сирим enum байтово, тож у en пін
    # механізму не бачив би.
    it "renders from/to AASM states through StatusBadge labels" do
      # [TEST.12] Реальна форма писача — `naas_contract_to_<state>` (`naas_contract.rb`);
      # доти фікстура вигадувала `naas_contract_cancelled` без `_to_`.
      transition = build_log(action: "naas_contract_to_cancelled", metadata: { "from" => "draft", "to" => "cancelled" })
      expect(I18n.with_locale(:uk) { render_component(log: transition) }).to include("чернетка")
    end

    it "renders from/to of user_role_changed through role labels" do
      role_change = build_log(action: "user_role_changed", metadata: { "from" => "forester", "to" => "admin" })
      expect(I18n.with_locale(:uk) { render_component(log: role_change) }).to include("Лісник")
    end

    it "leaves non-status from/to values raw (fail-open)" do
      rotation = build_log(action: "stream_epoch_rotated", metadata: { "from" => "7781", "to" => "7782" })
      expect(render_component(log: rotation)).to include("7781")
    end
  end

  # [I18N.1] Мітки дії — дім `ActionBadge.label` (деривація має власну спеку
  # в `spec/views/shared/ui/action_badge_spec.rb`); тут пінимо ПРОВОДКУ:
  # обидва хазяї (h2 + бейдж) кличуть дім і передають metadata. aria-label
  # знято свідомо — над локалізованим видимим текстом він перекривав би
  # accessible name (ратифіковане правило I18N.1).
  describe "action label wiring" do
    it "renders the transition family through its state home (uk)" do
      transition = build_log(action: "naas_contract_to_cancelled", metadata: { "from" => "draft", "to" => "cancelled" })
      expect(I18n.with_locale(:uk) { render_component(log: transition) }).to include("Контракт → скасовано")
    end

    it "resolves the event form via metadata to-state (uk)" do
      event = build_log(action: "blockchain_tx_confirm", metadata: { "from" => "sent", "to" => "confirmed" })
      expect(I18n.with_locale(:uk) { render_component(log: event) }).to include("Транзакція → підтверджено")
    end

    it "keeps the raw token in the details row (людське ⊥ машинне)" do
      expect(html).to include(">system_parameter_changed<")
    end
  end

  describe "actor info" do
    it "renders Actor Identity heading" do
      expect(html).to include("Actor Identity")
    end

    it "renders actor full name" do
      expect(html).to include("Ada Lovelace")
    end

    it "renders actor email" do
      expect(html).to include("ada@silkennet.com")
    end

    # [I18N.1] Локаль НЕ базова: «admin» є підрядком «Administrator», тож у en пін не
    # розрізняв би сирий enum від мітки.
    it "renders actor role as a human label" do
      expect(I18n.with_locale(:uk) { render_component(log: log) }).to include("Адміністратор")
    end

    it "renders System actor notice for system logs" do
      system_log = build_log(user: nil)
      html = render_component(log: system_log)
      expect(html).to include("System actor")
    end
  end

  describe "target info" do
    it "renders Auditable Target heading" do
      expect(html).to include("Auditable Target")
    end

    it "renders auditable type" do
      expect(html).to include("Tree")
    end

    it "renders auditable id" do
      expect(html).to include("42")
    end

    it "renders no specific target notice when auditable_type is blank" do
      log_no_target = build_log(auditable_type: nil, auditable_id: nil)
      html = render_component(log: log_no_target)
      expect(html).to include("No specific target")
    end
  end

  describe "актор без імені" do
    # 🔴 Приклад, який доти НЕ МІГ існувати: мок задавав `full_name` полем, тож
    # фолбек «імен немає → показуємо адресу» був недосяжний за побудовою. На
    # аудит-екрані це ШТАТНА поведінка (внутрішня сторінка), і саме тому її треба
    # закріпити: той самий фолбек на ЗОВНІШНІХ поверхнях є витоком PII, і межа
    # проходить по тому, хто читає сторінку, а не по зручності методу.
    it "друкує адресу там, де імені немає — і це навмисно, бо екран внутрішній" do
      nameless = User.new(email_address: "ranger@silkennet.com", role: :forester)
      html = render_component(log: build_log(user: nameless))

      # ⚠️ Пін МУСИТЬ цілити у вузол ІМЕНІ: адреса рендериться ще й окремим рядком
      # нижче, тож `include("ranger@…")` по документу зелений незалежно від фолбеку —
      # мутація «прибрати `|| email_address`» його не червонила (перевірено).
      expect(html).to include(%(<p class="text-compact text-gaia-text font-mono">ranger@silkennet.com</p>))
    end
  end
end
