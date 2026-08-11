# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::Settings do
  # Усі чотири канали — справжні колонки `users`, тож фікстура годує сам запис.
  # [SEC.25] Дзеркало `settings#update`: контролер віддає сюди `current_user`
  # після невдалого `update` (телефон не в E.164), тому `errors` — частина
  # реального контракту; доти вони підроблялись `double`, тобто спека сама
  # вирішувала, що поверне ActiveModel. Заразом зникли рукописні
  # `model_name`/`to_key`/`to_param`: компонент їх не читає ЖОДНОГО разу —
  # форма тут рукописна й адресується `notifications_settings_path`.
  def account(email_address: "ada@silken.net", phone_number: "+380501234567",
              telegram_chat_id: "123456789", push_token: nil)
    User.new(
      email_address: email_address,
      phone_number: phone_number,
      telegram_chat_id: telegram_chat_id,
      push_token: push_token
    )
  end

  let(:user) { account }
  let(:html) { render_component(user: user) }

  describe "header section" do
    it "renders Neural Web heading" do
      expect(html).to include("Neural Web")
    end

    it "renders Notification Channels subtitle" do
      expect(html).to include("Notification Channels")
    end
  end

  describe "form fields" do
    it "renders email field as disabled" do
      expect(html).to include("ada@silken.net")
      expect(html).to include("disabled")
    end

    it "renders phone number field" do
      expect(html).to include("phone_number")
      expect(html).to include("+380501234567")
    end

    it "renders telegram_chat_id field" do
      expect(html).to include("telegram_chat_id")
      expect(html).to include("123456789")
    end

    it "renders push_token field" do
      expect(html).to include("push_token")
    end

    it "renders submit button" do
      expect(html).to include("Save Channels")
    end
  end

  describe "channel status indicators" do
    it "renders Email channel status" do
      expect(html).to include("Email")
    end

    it "renders SMS / Phone channel status" do
      expect(html).to include("SMS")
    end

    it "renders Telegram channel status" do
      expect(html).to include("Telegram")
    end

    it "renders Push channel status" do
      expect(html).to include("Push")
    end

    # 🔴 Обидва піни доти дивились на ВЕСЬ документ, тобто не вміли сказати, ЯКИЙ
    # саме канал підключено: три рядки з чотирьох підключені, і «Connected»
    # знаходився в будь-якому разі. Тепер ціль — пара «мітка → стан» в одному
    # вузлі, тож підміна предиката рядка (`push_token` на будь-який заповнений)
    # червонить поіменно.
    it "binds a configured channel to its own Connected marker" do
      expect(html).to include('Telegram</span><div class="flex items-center gap-2">')
    end

    it "binds the empty push_token to its own Not-configured marker" do
      expect(html).to include(
        %(<span class="text-tiny text-gray-400 font-mono">🔔 Push</span><span class="text-mini text-gray-700 uppercase">Not configured</span>)
      )
    end
  end

  # Гілку підсумку помилок не виконував ЖОДЕН приклад: фікстура вміла їх приймати
  # (`error_messages:`), але жоден приклад їх не подавав, тож єдиний шлях, яким
  # людина бачить причину 422, у сюїті не проходився ніколи.
  describe "validation errors from a rejected update" do
    let(:user) { account.tap { |u| u.errors.add(:phone_number, :invalid) } }

    it "renders the reason the update was refused" do
      expect(html).to include("Phone number is invalid")
    end
  end

  describe "notification types list" do
    it "renders Critical Alerts type" do
      expect(html).to include("Critical")
    end

    it "renders Warning Alerts type" do
      expect(html).to include("Warning")
    end

    it "renders Minting Events type" do
      expect(html).to include("Minting")
    end

    it "renders Slashing Events type" do
      expect(html).to include("Slashing")
    end

    it "renders System Health type" do
      expect(html).to include("System Health")
    end

    it "shows ACTIVE for all notification types" do
      active_count = html.scan("ACTIVE").length
      expect(active_count).to be >= 5
    end
  end

  describe "Active Channels section" do
    it "renders Active Channels heading" do
      expect(html).to include("Active Channels")
    end
  end
end
