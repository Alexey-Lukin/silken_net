# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SystemHealth::Show do
  # Форма беруться з того, що будує контролер (`SystemHealthController#show`),
  # а не вигадується: доти фікстура несла ключ `sidekiq[:alive]`, якого
  # контролер не віддавав, і рядок помилки `"Connection refused"`, який він
  # перестав емітити після SEC-фіксу — тобто спека стерегла контракт, якого
  # вже не існувало.
  def health(coap: { status: "alive", host: "api.silkennet.com", port: 5683 },
             sidekiq: { alive: true, processes: 2, enqueued: 3, processed: 100,
                        failed: 0, workers_size: 2, queues: { "uplink" => 0, "default" => 2 } },
             database: { connected: true })
    {
      coap_listener: coap,
      sidekiq: sidekiq,
      database: database,
      # Форма — та, яку кладе контролер (`Time.current.iso8601`), а не людяний
      # штамп: інакше спека показує екран, якого адміністратор не бачить.
      checked_at: "2024-01-15T12:00:00Z"
    }
  end

  let(:html) { render_component(health: health) }

  # [UI.1 сигнальна хвиля] Тони крапок — токенні акценти, не сира палітра:
  # `bg-amber-500` давав 1.95–2.15 у світлій, `bg-red-500` — 2.4; мутація
  # «сирий колір назад» червонить відповідний приклад поіменно.
  describe "status dot tones" do
    it "paints ok with the strong token" do
      expect(html).to include("bg-gaia-primary-strong")
      expect(html).not_to include("bg-emerald-500")
    end

    it "paints unknown with the warning accent — never the raw amber" do
      rendered = render_component(health: health(coap: { status: "not_configured" }))

      expect(rendered).to include("bg-status-warning-accent")
      expect(rendered).not_to include("bg-amber-500")
    end

    it "paints down with the pulsing danger accent" do
      rendered = render_component(health: health(database: { connected: false }))

      expect(rendered).to include("bg-status-danger-accent")
      expect(rendered).to include("animate-pulse")
      expect(rendered).not_to include("bg-red-500")
    end
  end

  describe "header section" do
    it "renders Pulse Monitor heading" do
      expect(html).to include("Pulse Monitor")
    end

    it "renders ALL SYSTEMS GO when all healthy" do
      expect(html).to include("ALL SYSTEMS GO")
    end

    it "renders DEGRADED when a subsystem is affirmatively down" do
      rendered = render_component(health: health(coap: { status: "unreachable", host: "api.silkennet.com", port: 5683 }))
      expect(rendered).to include("DEGRADED")
    end
  end

  describe "overall banner" do
    it "renders the operational banner when all systems go" do
      expect(html).to include("ALL SUBSYSTEMS OPERATIONAL")
    end

    it "renders the degraded banner when a subsystem is down" do
      rendered = render_component(health: health(database: { connected: false }))
      expect(rendered).to include("SYSTEM DEGRADED")
    end

    # [ARCH.81] Несучий пін третього стану. «Не сконфігуровано» — це не «мертво»:
    # якби вони світились однаково, панель знову навчала б ігнорувати червоне,
    # лише поверхом вище за саму пробу. І це не «все добре» також.
    it "renders neither GO nor DEGRADED when a probe cannot report at all" do
      rendered = render_component(health: health(coap: { status: "not_configured", port: 5683 }))

      expect(rendered).to include("INCOMPLETE PICTURE")
      expect(rendered).not_to include("ALL SUBSYSTEMS OPERATIONAL")
      expect(rendered).not_to include("SYSTEM DEGRADED")
    end
  end

  describe "CoAP card" do
    it "renders the card with the probed address" do
      expect(html).to include("CoAP Listener")
      expect(html).to include("api.silkennet.com")
      expect(html).to include("5683")
    end

    it "renders LISTENING when the daemon answered with the expected bytes" do
      expect(html).to include("LISTENING")
    end

    it "renders NO REPLY when the datagram went unanswered" do
      rendered = render_component(health: health(coap: { status: "unreachable", host: "api.silkennet.com", port: 5683 }))
      expect(rendered).to include("NO REPLY")
    end

    # Відповідь прийшла, але не тими байтами — тобто на порту хтось інший або
    # граматика Брами розійшлась із freeze-contract. Це власний стан, а не
    # різновид мовчання.
    it "renders WIRE MISMATCH when the reply did not match the freeze-contract" do
      rendered = render_component(health: health(coap: { status: "wire_mismatch", host: "api.silkennet.com", port: 5683 }))
      expect(rendered).to include("WIRE MISMATCH")
    end

    it "renders a dash for the address when none is configured" do
      rendered = render_component(health: health(coap: { status: "not_configured", port: 5683 }))
      expect(rendered).to include("NOT CONFIGURED")
      expect(rendered).to include("—")
    end
  end

  describe "Sidekiq card" do
    it "renders the process count, which is what the card's name asks" do
      expect(html).to include("Sidekiq Workers")
      expect(html).to include("Processes")
    end

    it "renders queue distribution table when queues present" do
      expect(html).to include("Queue Distribution")
      expect(html).to include("uplink")
      expect(html).to include("default")
    end

    it "marks the card down when no worker process is registered" do
      rendered = render_component(health: health(
        sidekiq: { alive: false, processes: 0, enqueued: 3, processed: 100,
                   failed: 0, workers_size: 0, queues: {} }
      ))
      expect(rendered).to include("SYSTEM DEGRADED")
    end

    it "renders the sidekiq error marker when the stats call failed" do
      rendered = render_component(health: health(sidekiq: { alive: false, error: "check_failed" }))
      expect(rendered).to include("check_failed")
    end
  end

  describe "Database card" do
    it "renders PostgreSQL card" do
      expect(html).to include("PostgreSQL")
    end

    it "renders ACTIVE connection status when connected" do
      expect(html).to include("ACTIVE")
    end

    it "renders DISCONNECTED status when the round-trip failed" do
      rendered = render_component(health: health(database: { connected: false }))
      expect(rendered).to include("DISCONNECTED")
    end
  end

  describe "footer" do
    it "renders last checked timestamp" do
      expect(html).to include("Last checked at 2024-01-15T12:00:00Z")
    end
  end
end
