# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Provisioning::New do
  # Реальні незбережені записи: `collection_select` бере з них лише `:id`/`:name`,
  # тож виготовлені доти `model_name`/`to_key`/`to_param` були мертвими стабами —
  # оголошеним контрактом із фреймворком, якого жоден приклад не перевіряв.
  def build_cluster(id: 1, name: "Carpathian-Alpha") = Cluster.new(id: id, name: name)
  def build_family(id: 1, name: "Oak") = TreeFamily.new(id: id, name: name)

  # Причини провалу провіжнінгу приходять на `:base` (`render_new_with_errors`
  # добудовує порожній `Tree`, коли пристрій ще не збудовано), тож `full_messages`
  # віддає їх ДОСЛІВНО. Доти фікстура імітувала атрибутну помилку про поле
  # `hardware_uid`, якого на `Tree` немає, — форму, якої цей тракт не виробляє.
  def device_with_error(message)
    Tree.new.tap { |t| t.errors.add(:base, message) }
  end

  let(:clusters) { [ build_cluster ] }
  let(:families) { [ build_family ] }
  let(:html)     { render_component(clusters: clusters, families: families) }

  describe "header section" do
    # [I18N.1-нейминг] Заголовок компонента був підмножиною заголовка сторінки
    # («Hardware Initiation» проти «Hardware Initiation Ritual»).
    it "does not duplicate the page name the layout already renders" do
      expect(html).not_to include("Hardware Initiation")
    end

    it "renders biometric link subtitle" do
      expect(html).to include("biometric link")
    end
  end

  describe "form fields" do
    it "renders hardware_uid field" do
      expect(html).to include("hardware_uid")
    end

    it "renders Physical Crystal ID label" do
      expect(html).to include("Physical Crystal ID")
    end

    it "renders device_type select with Soldier option" do
      expect(html).to include("Soldier")
    end

    it "renders device_type select with Queen option" do
      expect(html).to include("Queen")
    end

    it "renders cluster selection" do
      expect(html).to include("Carpathian-Alpha")
    end

    it "renders family selection" do
      expect(html).to include("Oak")
    end

    it "renders latitude field" do
      expect(html).to include("latitude")
    end

    it "renders longitude field" do
      expect(html).to include("longitude")
    end
  end

  describe "submit button" do
    it "renders BIND HARDWARE TO MATRIX button" do
      expect(html).to include("BIND HARDWARE TO MATRIX")
    end
  end

  describe "error display" do
    it "renders validation errors when device has errors" do
      message = I18n.t("flash.provisioning.uid_taken", uid: "SNET-Q-AABB0011")
      html = render_component(
        clusters: clusters, families: families, device: device_with_error(message)
      )
      expect(html).to include("Initiation Failed")
      # Дослівно, без префікса атрибута: причина з guard-клаузи їде на `:base`,
      # і саме це відрізняє її від модельної валідації в очах лісника.
      expect(html).to include(message)
    end

    it "does not render error section when device is nil" do
      expect(html).not_to include("Initiation Failed")
    end
  end
end
