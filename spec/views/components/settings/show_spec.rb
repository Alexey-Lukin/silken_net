# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Settings::Show do
  # [SEC.25] Контролер передає сюди справжню `Organization` — ту саму, чиї
  # `errors` він щойно наповнив невдалим `update`.
  # [TEST.12] Тепер це реальний незбережений запис, і конверсія знімає дві
  # вигадки. Адреса доти мала 12 символів при `ETH_ADDRESS_FORMAT` на 42 —
  # значення, недосяжне для будь-якого записаного рядка, і саме через його
  # довжину скорочення у сховищі особистості не спрацьовувало НІКОЛИ.
  # Пороги — `numeric`, тож їх форму тепер видно з сюїти.
  def build_org(name: "Forest Org", billing_email: "billing@org.org",
                crypto_public_address: "0x1234567890abcdef1234567890abcdef12345678",
                alert_threshold_critical_z: 2.5, ai_sensitivity: 0.7,
                id: 1, created_at: 2.years.ago, updated_at: 1.hour.ago,
                logo_attached: false, error_messages: [])
    org = Organization.new(
      name: name,
      billing_email: billing_email,
      crypto_public_address: crypto_public_address,
      alert_threshold_critical_z: alert_threshold_critical_z,
      ai_sensitivity: ai_sensitivity,
      id: id,
      created_at: created_at,
      updated_at: updated_at
    )
    error_messages.each { |m| org.errors.add(:base, m) }
    # Блоб без БД не збудувати — стаб іде через RSpec-API, тож `verify_partial_doubles`
    # звіряє, що `logo` на моделі взагалі існує (`OpenStruct` цього не робив).
    #
    # ⚠️ Сам повернений об'єкт verifying double бути НЕ може: справжній клас —
    # `ActiveStorage::Attached::One`, а `filename` там не оголошено статично, він
    # їде через `delegate_missing_to :attachment`. `instance_double` бачить лише
    # реальні методи класу, тож падає «does not implement … filename» (виміряно на
    # всіх 23 прикладах). `object_double` теж не рятує: без attachment
    # `respond_to?(:filename)` == false.
    allow(org).to receive(:logo).and_return(
      double("logo", attached?: logo_attached, filename: ActiveStorage::Filename.new("logo.png")) # rubocop:disable RSpec/VerifiedDoubles
    )
    org
  end

  def render_component(organization:)
    ApplicationController.renderer.render(
      component_class.new(organization: organization),
      layout: false
    )
  end

  let(:org) { build_org }
  let(:html) { render_component(organization: org) }

  describe "settings form" do
    # 🔴 [UI.3] Пін парсить розмітку, а не шукає рядок: сусідні приклади пінять текст
    # мітки й імена полів, тобто голий `<label>` без `for` лишався б зеленим, поки
    # скрінрідер поля не називає (WCAG 1.3.1). ⚠️ Селект локалі `for` мав ще доти —
    # тобто форма була напів-звʼязана, і саме така асиметрія найтихіша.
    it "associates every label with a real form control" do
      doc = Nokogiri::HTML5.fragment(html)

      expect(doc.css("label")).not_to be_empty, "no labels rendered — the pin would be vacuous"
      expect(LabelAssociation.orphan_labels(doc).map { |l| l.text.strip }).to be_empty
    end

    it "renders the Configuration heading" do
      expect(html).to include("Configuration")
    end

    it "renders the form action to settings_path" do
      expect(html).to include("/settings")
    end

    it "renders a PATCH form via hidden method" do
      expect(html).to include('value="patch"')
    end
  end

  describe "name field" do
    it "renders the organization name input" do
      expect(html).to include('name="organization[name]"')
    end

    it "pre-fills the current name" do
      expect(html).to include("Forest Org")
    end
  end

  describe "billing email field" do
    it "renders the billing email input" do
      expect(html).to include('name="organization[billing_email]"')
    end

    it "pre-fills the current billing email" do
      expect(html).to include("billing@org.org")
    end

    it "renders the input without a pre-filled value when billing_email is nil" do
      org = build_org(billing_email: nil)
      rendered = render_component(organization: org)
      expect(rendered).to include('name="organization[billing_email]"')
    end
  end

  describe "crypto address field" do
    it "renders the crypto public address input" do
      expect(html).to include('name="organization[crypto_public_address]"')
    end

    it "pre-fills the crypto address in full — the field is editable" do
      expect(html).to include(%(value="#{org.crypto_public_address}"))
    end
  end

  describe "logo upload" do
    it "renders the Organization Logo field" do
      expect(html).to include("Organization Logo")
    end

    it "renders a file input for the logo" do
      expect(html).to include('name="organization[logo]"')
    end
  end

  describe "identity vault section" do
    it "renders the On-Chain Identity Vault heading" do
      expect(html).to include("On-Chain Identity Vault")
    end

    # Доти цей приклад був вакуумний: ту саму адресу друкує поле форми вище,
    # тож він лишався зеленим і зі знесеним сховищем. Цілимо у ВУЗОЛ під міткою.
    it "renders billing contact in the vault" do
      # [UI.1 08-20] Пін їде за міграцією домену: сирий gray-400 → токен.
      expect(html).to include(%(<p class="text-compact text-gaia-text-subtle">billing@org.org</p>))
    end

    # Сховище показує адресу СКОРОЧЕНОЮ, форма — повною. Доти розрізнити ці
    # два шляхи було неможливо: фікстура подавала адресу, коротшу за поріг
    # скорочення, тож обидва друкували те саме.
    it "truncates the address in the vault, unlike the editable field" do
      expect(html).to include("0x1234…5678")
    end
  end

  describe "update button" do
    it "renders the Update Settings button" do
      expect(html).to include("Update Settings")
    end
  end

  describe "alert threshold and AI sensitivity fields" do
    it "renders alert_threshold_critical_z field" do
      expect(html).to include('name="organization[alert_threshold_critical_z]"')
    end

    it "renders ai_sensitivity field" do
      expect(html).to include('name="organization[ai_sensitivity]"')
    end

    # Обидві колонки `numeric`, тобто модель віддає BigDecimal — доти сюїта
    # пінила лише ІМЕНА полів, тож питання «що оператор бачить у полі порогу»
    # з неї неможливо було поставити.
    it "pre-fills both thresholds with the value the operator will see" do
      expect(html).to include('value="2.5"')
      expect(html).to include('value="0.7"')
    end
  end

  describe "system metadata" do
    # Секція не мала жодного прикладу, хоча друкує ідентифікатор організації
    # і дві дати у власних форматах.
    it "renders the organization id and both timestamps" do
      expect(html).to include("System Metadata")
      expect(html).to include(">1<")
      expect(html).to include(org.created_at.strftime("%d.%m.%Y"))
      expect(html).to include(org.updated_at.strftime("%d.%m.%Y %H:%M"))
    end
  end

  describe "logo attached" do
    it "renders current logo filename when attached" do
      org = build_org(logo_attached: true)
      html = render_component(organization: org)
      expect(html).to include("Current: logo.png")
    end

    it "does not render current logo filename when not attached" do
      expect(html).not_to include("Current:")
    end
  end
end
