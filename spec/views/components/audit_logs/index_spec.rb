# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditLogs::Index do
  def build_user(name: "Ada Lovelace")
    # [TEST.12] Реальний `User`: `full_name` тепер ФОРМУЛА
    # (`[first,last].compact_blank.join(" ").presence || email_address`), а не поле —
    # тобто фікстура годує імена, а не результат. Аудит-екран законно лишається на
    # `full_name` (внутрішній, `04_04` / скіл `frontend`), тож саме тут фолбек на
    # адресу є штатною поведінкою, і подавати готовий рядок означало б її сховати.
    first, last = name.to_s.split(" ", 2)
    User.new(first_name: first, last_name: last)
  end

  # [TEST.12] `action:` — лише РЕАЛЬНІ значення писачів: доти дефолти
  # «create»/«update»/«destroy» були CRUD-стилем, якого домен не пише ніде.
  def build_log(id: 1, action: "system_parameter_changed", auditable_type: "Tree", auditable_id: 99,
               user: nil, created_at: Time.current)
    log = AuditLog.new(
      id: id,
      action: action,
      auditable_type: auditable_type,
      auditable_id: auditable_id,
      user: user,
      created_at: created_at
    )
    log
  end

  let(:log_with_user)    { build_log(id: 1, action: "user_role_changed", auditable_type: "Tree", auditable_id: 7, user: build_user) }
  let(:log_without_user) { build_log(id: 2, action: "stream_epoch_rotated", auditable_type: nil, auditable_id: nil, user: nil) }
  let(:logs)             { [ log_with_user, log_without_user ] }
  let(:html)             { render_component(logs: logs, pagy: mock_pagy(count: 63)) }

  describe "header" do
    it "renders the Watcher heading" do
      expect(html).to include("The Watcher")
    end

    it "renders the Audit Log label" do
      expect(html).to include("Audit Log")
    end

    it "renders record count from pagy" do
      expect(html).to include("Records:")
      expect(html).to include("63")
    end
  end

  describe "table headers" do
    it "renders Timestamp column" do
      expect(html).to include("Timestamp")
    end

    it "renders User column" do
      expect(html).to include("User")
    end

    it "renders Action column" do
      expect(html).to include("Action")
    end

    it "renders Target column" do
      expect(html).to include("Target")
    end
  end

  describe "log rows" do
    it "renders user full name" do
      expect(html).to include("Ada Lovelace")
    end

    it "renders System for logs without a user" do
      expect(html).to include("System")
    end

    it "renders auditable type and id" do
      expect(html).to include("Tree #7")
    end

    it "renders Inspect link" do
      expect(html).to include("Inspect")
    end

    it "renders aria-label with log id" do
      expect(html).to include("Inspect audit log #1")
    end

    # [I18N.1] Свідок дротування бейджа в НЕ-базовій локалі: en-мітка дорівнює
    # humanize побайтово, тож механізм видимий лише тут.
    it "renders the localized action label in the row (uk)" do
      expect(I18n.with_locale(:uk) { render_component(logs: logs, pagy: mock_pagy(count: 63)) })
        .to include("Роль користувача змінено")
    end
  end

  describe "empty state" do
    it "renders empty state when no logs" do
      html = render_component(logs: [], pagy: mock_pagy(count: 0))
      expect(html).to include("No audit events recorded")
    end
  end

  describe "pagination" do
    it "renders pagination" do
      expect(html).to include("page=")
    end

    # 🔴 Фільтр мусить пережити перехід на сторінку 2. Інакше «View logs for X»
    # приводить на відфільтровану першу сторінку, а другий клік тихо повертає
    # ПОВНИЙ журнал організації — той самий клас UI.7, лише на клік глибше.
    it "carries the active filters into every page link" do
      html = render_component(logs: logs, pagy: mock_pagy(count: 63), filters: { user_id: 7 })
      expect(html).to include("user_id=7")
    end
  end

  describe "filter notice" do
    # Без цього індикатора відфільтрована сторінка візуально невідрізнима від
    # повної, тож порожній результат читається як «журнал аудиту порожній».
    it "announces a filtered view and offers a way back to the full log" do
      html = render_component(logs: logs, pagy: mock_pagy(count: 1), filters: { user_id: 7 })
      expect(html).to include("Filtered view")
      expect(html).to include("Show all")
    end

    it "stays silent when no filter is active" do
      expect(html).not_to include("Filtered view")
    end
  end
end
