# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Firmwares::Index do
  # 🔴 [TEST.12] Мок подавав `target_hardware`/`checksum`, а компонент читає
  # `target_hardware_type`/`binary_sha256` — `OpenStruct` мовчки віддавав `nil` на
  # обидва, тож ці дві колонки могли рендеритись порожніми вічно (пінилися лише їхні
  # ЗАГОЛОВКИ). `build_stubbed`, а не `.new`: рядок читається роут-хелпером
  # `deploy_firmware_path`, тобто потребує `id`, і `created_at` для `strftime`.
  def mock_firmware(id: 1, version: "1.4.2", target_hardware_type: "Tree",
                    binary_sha256: "abcdef1234567890AABB", created_at: Time.zone.local(2024, 3, 15, 10, 30))
    build_stubbed(:bio_contract_firmware, id: id, version: version,
                  target_hardware_type: target_hardware_type,
                  binary_sha256: binary_sha256, created_at: created_at)
  end

  def mock_inventory_stats
    {
      gateways: { "2.1.0" => 5, "2.0.0" => 3 },
      trees: { "1.4.2" => 100, "1.3.0" => 50 }
    }
  end

  describe "rendering" do
    let(:firmwares) { [ mock_firmware(id: 1), mock_firmware(id: 2, version: "1.3.0") ] }
    let(:html) { render_component(firmwares: firmwares, inventory_stats: mock_inventory_stats, pagy: mock_pagy(count: 2, last: 1)) }


    it "displays the inventory summary heading" do
      expect(html).to include("Forest Inventory (Version Distribution)")
    end

    it "displays the firmware registry heading" do
      expect(html).to include("Available Binary Evolutions")
    end

    it "renders the upload new firmware link" do
      expect(html).to include("+ Inject New Code")
    end

    it "renders table column headers" do
      expect(html).to include("Version")
      expect(html).to include("Target Hardware")
      expect(html).to include("Checksum (SHA-256)")
      expect(html).to include("Uploaded")
      expect(html).to include("Command")
    end

    it "renders firmware version" do
      expect(html).to include("v1.4.2")
    end

    # Пін цілить у САМІ комірки: `include("Tree")` по всьому документу проходив би
    # через заголовок «Soldiers (Trees)» і був би зелений за будь-якої поведінки.
    it "рендерить ЗНАЧЕННЯ цільового заліза й контрольної суми, а не лише їхні заголовки" do
      cells = Nokogiri::HTML5.fragment(html).css("tbody tr td").map { |td| td.text.strip }
      expect(cells).to include("Tree")
      expect(cells).to include("abcdef1234567890")
    end

    it "renders firmware rows with deploy button" do
      expect(html).to include("Order Evolution →")
    end

    # Прошивка, завантажена без бінара (лише `bytecode_payload`), хеша не має —
    # доти цю гілку покривав мок, що НЕ оголошував поля взагалі й тому віддавав nil.
    it "displays N/A when binary_sha256 is missing" do
      rendered = render_component(firmwares: [ mock_firmware(binary_sha256: nil) ],
                                  inventory_stats: mock_inventory_stats, pagy: mock_pagy(count: 1, last: 1))
      expect(rendered).to include("N/A")
    end

    it "displays a truncated binary_sha256 when present" do
      fw = mock_firmware(id: 3)
      fw.binary_sha256 = "0123456789abcdef0123456789abcdef"
      rendered = render_component(firmwares: [ fw ], inventory_stats: mock_inventory_stats, pagy: mock_pagy(count: 1, last: 1))
      expect(rendered).to include("0123456789abcdef")
    end
  end

  describe "inventory stats" do
    let(:html) { render_component(firmwares: [], inventory_stats: mock_inventory_stats, pagy: mock_pagy(count: 0, last: 1)) }

    it "displays Queens (Gateways) section" do
      expect(html).to include("Queens (Gateways)")
    end

    it "displays Soldiers (Trees) section" do
      expect(html).to include("Soldiers (Trees)")
    end

    it "displays version counts with units label" do
      expect(html).to include("units")
    end

    it "displays gateway version stats" do
      expect(html).to include("v2.1.0")
      expect(html).to include("5 units")
    end

    it "displays tree version stats" do
      expect(html).to include("v1.4.2")
      expect(html).to include("100 units")
    end
  end

  describe "active OTA evolutions (SEC.20)" do
    def mock_ota_gateway(uid: "SNET-Q-01", updating: true)
      gw = OpenStruct.new(uid: uid)
      gw.define_singleton_method(:updating?) { updating }
      gw
    end

    it "does not render the section without active campaigns" do
      html = render_component(firmwares: [], inventory_stats: mock_inventory_stats, pagy: mock_pagy(count: 0, last: 1))
      expect(html).not_to include("Active Evolutions")
    end

    it "renders subscription + progress bar per updating gateway" do
      html = render_component(
        firmwares: [], inventory_stats: mock_inventory_stats, pagy: mock_pagy(count: 0, last: 1),
        active_ota_gateways: [ mock_ota_gateway(uid: "SNET-Q-01") ]
      )
      expect(html).to include("Active Evolutions // Live OTA")
      expect(html).to include("turbo-cable-stream-source")
      expect(html).to include("ota_progress_SNET-Q-01")
      expect(html).to include("TRANSMITTING")
    end

    it "renders PENDING for a targeted gateway that has not polled yet" do
      html = render_component(
        firmwares: [], inventory_stats: mock_inventory_stats, pagy: mock_pagy(count: 0, last: 1),
        active_ota_gateways: [ mock_ota_gateway(uid: "SNET-Q-02", updating: false) ]
      )
      expect(html).to include("PENDING")
    end
  end

  describe "accessibility" do
    let(:html) { render_component(firmwares: [ mock_firmware ], inventory_stats: mock_inventory_stats, pagy: mock_pagy(last: 1)) }

    it "renders table with role=table" do
      expect(html).to include('role="table"')
    end

    it "includes aria-label on upload link" do
      expect(html).to include("Upload new firmware binary")
    end

    it "includes focus-visible ring styling" do
      expect(html).to include("focus-visible:ring-2")
    end
  end

  describe "best practices compliance" do
    let(:html) { render_component(firmwares: [ mock_firmware ], inventory_stats: mock_inventory_stats, pagy: mock_pagy(last: 1)) }

    it "uses text-tiny for typography" do
      expect(html).to include("text-tiny")
    end

    it "uses text-mini for small labels" do
      expect(html).to include("text-mini")
    end

    it "uses tracking-widest for uppercase labels" do
      expect(html).to include("tracking-widest")
    end
  end
end
