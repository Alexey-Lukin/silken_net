# frozen_string_literal: true

module Views
  module Shared
    module UI
      class StatusBadge < ApplicationComponent
        STYLES = {
          # AASM: BlockchainTransaction states
          "pending"      => "bg-yellow-900 text-yellow-200",
          "processing"   => "bg-amber-900 text-amber-200 animate-pulse",
          "sent"         => "bg-blue-900 text-blue-200",
          "confirmed"    => "bg-emerald-800 text-emerald-100",
          "failed"       => "bg-red-900 text-red-200",
          # AASM: ActuatorCommand states
          "issued"       => "bg-yellow-900 text-yellow-200",
          "acknowledged" => "bg-emerald-900 text-emerald-200",
          # AASM: EwsAlert states
          "active"       => "bg-red-900 text-red-200",
          "resolved"     => "bg-zinc-800 text-zinc-300 opacity-50",
          "ignored"      => "bg-zinc-800 text-zinc-300 opacity-30 line-through",
          # AASM: ParametricInsurance states
          "triggered"    => "bg-amber-900 text-amber-200 animate-pulse",
          "paid"         => "bg-blue-900 text-blue-200",
          "expired"      => "bg-zinc-800 text-zinc-400",
          # AASM: NaasContract states
          "draft"        => "bg-zinc-800 text-zinc-400",
          "fulfilled"    => "bg-emerald-800 text-emerald-100",
          "breached"     => "bg-red-900 text-red-200",
          "cancelled"    => "bg-zinc-800 text-zinc-400 opacity-50",
          # AASM: Gateway states
          "idle"         => "bg-zinc-800 text-zinc-400",
          "updating"     => "bg-amber-900 text-amber-200 animate-pulse",
          "maintenance"  => "bg-blue-900 text-blue-200",
          "faulty"       => "bg-red-900 text-red-200",
          # AASM: Tree states
          "dormant"      => "bg-amber-900 text-amber-200",
          "removed"      => "bg-zinc-800 text-zinc-400 opacity-50",
          "deceased"     => "bg-red-900 text-red-200 line-through",
          # AASM: Actuator states
          "offline"            => "bg-zinc-800 text-zinc-400",
          "maintenance_needed" => "bg-amber-900 text-amber-200"
        }.freeze

        DEFAULT_STYLE = "bg-zinc-800 text-zinc-300"

        def initialize(status:, id: nil)
          @status = status.to_s
          @id = id
        end

        def view_template
          style = STYLES.fetch(@status, DEFAULT_STYLE)

          span(
            id: @id,
            class: tokens("px-2 py-0.5 rounded text-[10px] font-bold uppercase", style)
          ) { @status }
        end
      end
    end
  end
end
