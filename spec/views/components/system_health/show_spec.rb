# frozen_string_literal: true

require "rails_helper"

RSpec.describe SystemHealth::Show do
  def healthy_health(queues: { "uplink" => 0, "default" => 2 })
    {
      coap_listener: { alive: true, port: 5683, error: nil },
      sidekiq: { alive: true, error: nil, enqueued: 3, processed: 100, failed: 0, workers_size: 2, queues: queues },
      database: { connected: true, error: nil },
      checked_at: "2024-01-15 12:00:00 UTC"
    }
  end

  def degraded_health
    {
      coap_listener: { alive: false, port: 5683, error: "Connection refused" },
      sidekiq: { alive: true, error: nil, enqueued: 0, processed: 0, failed: 0, workers_size: 0, queues: {} },
      database: { connected: true, error: nil },
      checked_at: "2024-01-15 12:00:00 UTC"
    }
  end

  let(:html) { render_component(health: healthy_health) }

  describe "header section" do
    it "renders Pulse Monitor heading" do
      expect(html).to include("Pulse Monitor")
    end

    it "renders ALL SYSTEMS GO when all healthy" do
      expect(html).to include("ALL SYSTEMS GO")
    end

    it "renders DEGRADED when system is unhealthy" do
      html = render_component(health: degraded_health)
      expect(html).to include("DEGRADED")
    end
  end

  describe "overall status banner" do
    it "renders operational banner when all systems go" do
      expect(html).to include("ALL SUBSYSTEMS OPERATIONAL")
    end

    it "renders degraded banner when system is degraded" do
      html = render_component(health: degraded_health)
      expect(html).to include("SYSTEM DEGRADED")
    end
  end

  describe "CoAP card" do
    it "renders CoAP Listener card" do
      expect(html).to include("CoAP Listener")
    end

    it "renders port 5683" do
      expect(html).to include("5683")
    end

    it "renders LISTENING status when alive" do
      expect(html).to include("LISTENING")
    end

    it "renders OFFLINE status when not alive" do
      html = render_component(health: degraded_health)
      expect(html).to include("OFFLINE")
    end

    it "renders error message when CoAP has error" do
      html = render_component(health: degraded_health)
      expect(html).to include("Connection refused")
    end
  end

  describe "Sidekiq card" do
    it "renders Sidekiq Workers card" do
      expect(html).to include("Sidekiq Workers")
    end

    it "renders queue distribution table when queues present" do
      expect(html).to include("Queue Distribution")
    end

    it "renders queue names" do
      expect(html).to include("uplink")
      expect(html).to include("default")
    end
  end

  describe "Database card" do
    it "renders PostgreSQL card" do
      expect(html).to include("PostgreSQL")
    end

    it "renders ACTIVE connection status when connected" do
      expect(html).to include("ACTIVE")
    end
  end

  describe "Sidekiq error display" do
    it "renders sidekiq error message when present" do
      health = healthy_health
      health[:sidekiq][:error] = "Redis connection lost"
      html = render_component(health: health)
      expect(html).to include("Redis connection lost")
    end
  end

  describe "Database error display" do
    it "renders database error message when present" do
      health = healthy_health
      health[:database][:error] = "Too many connections"
      html = render_component(health: health)
      expect(html).to include("Too many connections")
    end
  end

  describe "footer" do
    it "renders last checked timestamp" do
      expect(html).to include("Last checked at")
      expect(html).to include("2024-01-15 12:00:00 UTC")
    end
  end
end
