# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SilkenNet::LoadTest::LorenzMicrobench do
  it "міряє pure-compute throughput по thread-count'ах" do
    result = described_class.run(iterations_per_thread: 200, thread_counts: [ 1, 2 ])

    expect(result.keys).to eq([ 1, 2 ])
    result.each_value do |m|
      expect(m[:throughput]).to be > 0
      expect(m[:wall_s]).to be > 0
      expect(m[:total_iters]).to eq(m[:threads] * 200)
    end
  end

  it "документує GVL-стелю: pure-Ruby Float-цикл не масштабується лінійно з тредами" do
    # На MRI GVL серіалізує байткод → 2 треди НЕ подвоюють throughput.
    # М'який поріг (не жорсткий 1.0×) — залишає люфт на timer-jitter, але
    # суперлінійності (>2×) на GVL-bound роботі бути не може за визначенням.
    r = described_class.run(iterations_per_thread: 800, thread_counts: [ 1, 2 ])
    expect(r[2][:throughput]).to be < (2.0 * r[1][:throughput])
  end
end
