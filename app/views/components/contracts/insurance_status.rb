# frozen_string_literal: true

module Contracts
  class InsuranceStatus < ApplicationComponent
    STATUS_STYLES = {
      "active"    => "bg-emerald-900 text-emerald-200",
      "triggered" => "bg-amber-900 text-amber-200 animate-pulse",
      "paid"      => "bg-blue-900 text-blue-200",
      "expired"   => "bg-zinc-800 text-zinc-400"
    }.freeze

    def initialize(insurance:)
      @insurance = insurance
    end

    def view_template
      status = @insurance.status.to_s
      style  = STATUS_STYLES.fetch(status, "bg-zinc-800 text-zinc-300")

      span(
        id: "insurance_card_#{@insurance.id}",
        class: "px-2 py-1 rounded text-[10px] font-bold uppercase #{style}"
      ) { status }
    end
  end
end
