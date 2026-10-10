# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [FW.59] Коди причини ребуту — один перелік на обидва вузли; wire-дім — заголовок прошивки.
# Доти парність Ruby ⟷ C не пінив ніхто (фабрика пульсу свідомо бере літерали).
RSpec.describe ResetCause do
  let(:header) { Rails.root.join("firmware/common/reset_cause.h").read }

  it "maps every wire code exactly as firmware/common/reset_cause.h defines it" do
    codes = header.scan(/#define SILKEN_RESET_(\w+)\s+(\d+)u/).reject { |name, _| name == "CAUSE_MAX" }
                  .to_h { |name, code| [ code.to_i, name.downcase.to_sym ] }

    expect(codes.keys.sort).to eq((0..7).to_a)
    expect(described_class::CAUSES.each_with_index.to_h { |cause, i| [ i, cause ] }).to eq(codes)
  end

  it "puts in the fault bucket exactly the causes Silken_Reset_Cause_Is_Fault names" do
    body = header[/Silken_Reset_Cause_Is_Fault\(uint8_t cause\)\s*\{(.*?)\n\}/m, 1]
    named = body.scan(/cause == SILKEN_RESET_(\w+)/).flatten.map { |n| n.downcase.to_sym }

    expect(named).not_to be_empty
    expect(described_class::FAULT_CAUSES).to match_array(named)
  end

  it "reads an unknown code as the 'not reported' sentinel, never as a cause" do
    expect(described_class.from_code(9)).to eq(:unknown)
    expect(described_class.from_code(-1)).to eq(:unknown) # Array#fetch(-1) віддав би low_power
    expect(described_class.fault?(nil)).to be(false)
  end
end
