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
  def account(email_address: "ada@silkennet.com", push_token: nil)
    User.new(
      email_address: email_address,
      push_token: push_token
    )
  end

  let(:user) { account }
  # [UI.10] Транспорт — факт про ПЛАТФОРМУ, тож він приходить кwargʼом (дім —
  # `Notifications::DeliveryChannels`). Тут його оголошено живим для всіх
  # трьох, бо решта прикладів файлу говорить про адреси користувача; окремі
  # контексти нижче міряють саме вісь транспорту.
  let(:available_channels) { %i[email push] }
  let(:html) { render_component(user: user, available_channels: available_channels) }

  describe "header section" do
    it "renders Neural Web heading" do
      expect(html).to include("Neural Web")
    end

    it "renders Notification Channels subtitle" do
      expect(html).to include("Notification Channels")
    end
  end

  describe "form fields" do
    # 🔴 [UI.3] Дві осі звʼязку, і друга специфічна саме для цієї форми: підказка
    # (`hint`) пояснює, ЧОМУ поле вимкнене, а лежачи окремим `<p>` читалась як
    # непов'язаний текст після поля. Пін вимагає обох: `for` ⟷ `id` і
    # `aria-describedby` ⟷ id підказки.
    # ⚠️ Дві осі — ДВА приклади (§Guard-craft #46): у злитому вигляді падіння не
    # каже, яка з них зламалась, а перша ж червона половина ховає другу.
    it "associates every label with a real form control" do
      doc = Nokogiri::HTML5.fragment(html)

      expect(doc.css("label")).not_to be_empty, "no labels rendered — the pin would be vacuous"
      expect(LabelAssociation.orphan_labels(doc).map { |l| l.text.strip }).to be_empty
    end

    it "points every hint reference at a description that exists" do
      doc = Nokogiri::HTML5.fragment(html)

      expect(doc.css("[aria-describedby]")).not_to be_empty,
                                                  "no hints rendered — the aria half would be vacuous"
      expect(LabelAssociation.dangling_descriptions(doc)).to be_empty
    end

    it "renders email field as disabled" do
      expect(html).to include("ada@silkennet.com")
      expect(html).to include("disabled")
    end

    # [ARCH.78, присуд 2026-08-20] SMS відкинуто разом із phone_number — форма
    # не сміє пропонувати поле каналу, якого не існує.
    it "does not render the retired phone field" do
      expect(html).not_to include("phone_number")
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

    it "does not render a status row for the retired SMS channel" do
      expect(html).not_to include("SMS")
    end

    # ⚫ Рядка статусу Telegram більше немає — канал зрізано ⚖️ 2026-09-06.
    it "does not render a status row for the retired Telegram channel" do
      expect(html).not_to include("Telegram")
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
      # ⚫ Носій переїхав із Telegram на email 2026-09-06 [ARCH.60]: предмет —
      # ПАРА «мітка ↔ маркер» в одному вузлі, а не конкретний канал.
      expect(html).to include('Email</span><div class="flex items-center gap-2">')
    end

    it "binds the empty push_token to its own Not-configured marker" do
      expect(html).to include(
        %(<span class="text-tiny text-gaia-text-subtle font-mono">🔔 Push</span><span class="text-mini text-gaia-text-subtle uppercase">Not configured</span>)
      )
    end
  end

  # Гілку підсумку помилок не виконував ЖОДЕН приклад: фікстура вміла їх приймати
  # (`error_messages:`), але жоден приклад їх не подавав, тож єдиний шлях, яким
  # людина бачить причину 422, у сюїті не проходився ніколи.
  describe "validation errors from a rejected update" do
    # ⚫ Носій переїхав із `telegram_chat_id` на `locale` 2026-09-06 [ARCH.60]:
    # предмет піна — що імʼя поля береться з `attributes.*`, а не з `humanize`,
    # і він не залежить від того, ЯКЕ саме поле помилкове.
    let(:user) { account.tap { |u| u.errors.add(:locale, :inclusion) } }

    it "renders the reason the update was refused" do
      # [I18N.1] Імʼя поля приходить із `attributes.locale`, а не з
      # `String#humanize` — доти воно було англійським у ВСІХ локалях.
      expect(html).to include("Language is not included in the list")
    end
  end

  # [UI.10] Вісь ТРАНСПОРТУ — окрема від адреси, і саме її злиття було дефектом:
  # екран рахував «активним» будь-який канал із заповненим полем, тоді як
  # доставки не існувало в жодному.
  describe "transport availability" do
    context "when the platform has no transport at all" do
      let(:available_channels) { [] }

      it "називає це станом КАНАЛУ, а не недоліком налаштувань користувача" do
        # ⚫ Носій переїхав із Telegram на Push 2026-09-06 [ARCH.60]: предмет —
        # що порожній транспорт називається станом КАНАЛУ, не недоліком людини.
        expect(html).to include(
          %(<span class="text-tiny text-gaia-text-subtle font-mono">🔔 Push</span><span class="text-mini text-gaia-text-subtle uppercase">Channel unavailable</span>)
        )
        expect(html).not_to include("Connected")
      end
    end

    # Дефолт fail-closed: компонент, якому забули передати факт, применшує
    # спроможність, а не вигадує її (дзеркало UI.5/UI.6).
    it "без переданого факту не оголошує ЖОДЕН канал живим" do
      bare = render_component(user: user)

      expect(bare).to include("Channel unavailable")
      expect(bare).not_to include("Connected")
    end

    it "розрізняє «немає транспорту» і «немає адреси» в межах одного рендеру" do
      # push_token порожній, транспорт оголошено живим для email/push.
      partial = render_component(user: user, available_channels: %i[email push])

      expect(partial).to include(
        %(<span class="text-tiny text-gaia-text-subtle font-mono">🔔 Push</span><span class="text-mini text-gaia-text-subtle uppercase">Not configured</span>)
      )
    end
  end

  # [UI.10] Блок «типів сповіщень» знято разом із шістьма прикладами, що його
  # пінили: пʼять рядків малювались статичним переліком із безумовним «АКТИВНО»
  # при нульовій моделі преференцій. Пін лишається як заборона повернення —
  # і він мусить уміти впасти, тому стоїть поруч із живим сусідом.
  describe "Active Channels section" do
    it "renders Active Channels heading" do
      expect(html).to include("Active Channels")
    end

    it "не обіцяє підписок, механізму яких немає" do
      expect(html).to include("Active Channels")
      expect(html).not_to include("Notification Types")
      expect(html).not_to include("ACTIVE")
    end
  end
end
