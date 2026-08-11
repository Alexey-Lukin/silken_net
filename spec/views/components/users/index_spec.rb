# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::Index do
  # [TEST.12] Реальний незбережений `User` замість OpenStruct: БД не потрібна, а
  # метадані фреймворку (`model_name`/`to_key`/`to_param`) віддає сама модель — доти
  # вони були рукописні, тобто фікстура оголошувала контракт, якого не перевіряла.
  # 🔴 Головне, що це змінює: `role` тепер ходить через справжній enum, тож значення
  # поза ним кидає `ArgumentError` у конструкторі (перевірено рантаймом) — саме тому
  # фолбек-гілку нижче доводиться діставати стабом РИДЕРА, а не вигаданим рядком.
  def build_user(id: 1, first_name: "Ada", last_name: "Lovelace", role: :admin, last_seen_at: Time.current)
    User.new(
      id: id,
      first_name: first_name,
      last_name: last_name,
      role: role,
      last_seen_at: last_seen_at,
      email_address: "ada@silken.net"
    )
  end

  let(:admin_user)    { build_user(id: 1, first_name: "Ada", last_name: "Lovelace", role: "admin") }
  let(:forester_user) { build_user(id: 2, first_name: "Bob", last_name: "Oak", role: "forester") }
  let(:investor_user) { build_user(id: 3, first_name: "Carol", last_name: "Pine", role: "investor") }
  let(:users)         { [ admin_user, forester_user, investor_user ] }
  let(:html)          { render_component(users: users) }

  # 🔴 Ціль, а не наявність кнопки. Доти тут стояв `href: "#"` — «AUDIT»-колонка
  # рендерилась, лінк був видимий і клікабельний, і не вів НІКУДИ. Жодна спека
  # цього не пінила, бо всі перевіряли текст, а не адресу. [UI.7]
  describe "audit link target" do
    it "points each row at that user's own slice of the audit log" do
      expect(html).to include(
        %(href="#{Rails.application.routes.url_helpers.audit_logs_path(user_id: forester_user.id)}")
      )
    end

    it "leaves no placeholder targets behind" do
      expect(html).not_to include(%(href="#"))
    end
  end

  describe "header section" do
    it "renders the registry header text" do
      expect(html).to include("Organization Crew Registry")
    end

    it "renders the subtitle" do
      expect(html).to include("Authorized personnel")
    end
  end

  describe "table headers" do
    it "renders the Identity column" do
      expect(html).to include("Identity")
    end

    it "renders the Role / Access column" do
      expect(html).to include("Role")
    end

    it "renders the Neural Link State column" do
      expect(html).to include("Neural Link State")
    end

    it "renders the Audit column" do
      expect(html).to include("Audit")
    end
  end

  describe "user rows" do
    it "renders avatar with first character of first_name" do
      expect(html).to include("A")
    end

    it "falls back to the email's first character when first_name is nil" do
      user = build_user(id: 5, first_name: nil, last_name: nil)
      user.email_address = "zed@silken.net"
      html = render_component(users: [ user ])
      expect(html).to include(">z<")
    end

    it "renders full name" do
      expect(html).to include("Ada Lovelace")
    end

    it "renders admin role with red badge colors" do
      expect(html).to include("bg-red-900/50")
      expect(html).to include("admin")
    end

    it "renders forester role with emerald badge colors" do
      expect(html).to include("bg-emerald-900/50")
      expect(html).to include("forester")
    end

    it "renders investor role with blue badge colors" do
      expect(html).to include("bg-blue-900/50")
      expect(html).to include("investor")
    end

    # 🔴 [TEST.12] `super_admin` — РЕАЛЬНА четверта роль enum'а, і доти вона власного
    # стилю не мала: падала в той самий `else`, що й пошкоджене значення, тобто
    # найпривілейованіший акаунт на екрані був невідрізнимий від «невідомо що це».
    # Пін тримає обидві половини — свій колір Є і чужого фолбеку НЕМА.
    it "gives super_admin its own badge, distinct from the corrupted-value fallback" do
      html = render_component(users: [ build_user(id: 4, role: :super_admin) ])

      expect(html).to include("bg-amber-900/50")
      expect(html).not_to include("bg-zinc-800")
    end

    # ⚠️ Фолбек досяжний ЛИШЕ стабом ридера: на реальному записі enum кидає
    # `ArgumentError` просто в конструкторі, тож доти цю гілку «перевіряв» вхід
    # (`role: "guest"`), якого в проді не буває — той самий хід, яким [`UI.4`]
    # діставав інакше недосяжну гілку статусу.
    it "renders an unrecognized role with the zinc fallback" do
      broken = build_user(id: 5, first_name: "Gus", last_name: "Guest")
      allow(broken).to receive(:role).and_return("__not_a_role__")

      html = render_component(users: [ broken ])
      expect(html).to include("bg-zinc-800")
      expect(html).to include("__not_a_role__")
    end

    it "renders VIEW_LOGS link" do
      expect(html).to include("VIEW_LOGS")
    end

    it "shows Link offline for users without last_seen_at" do
      no_seen_user = build_user(id: 9, first_name: "Zero", last_name: "X", last_seen_at: nil)
      html = render_component(users: [ no_seen_user ])
      expect(html).to include("Link offline")
    end
  end

  describe "pagination" do
    it "renders pagination when pagy is provided" do
      html = render_component(users: users, pagy: mock_pagy(count: 63))
      expect(html).to include("page=")
    end

    it "does not render pagination when pagy is nil" do
      html = render_component(users: users, pagy: nil)
      expect(html).not_to include("?page=")
    end
  end
end
