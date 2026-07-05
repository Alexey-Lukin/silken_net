# frozen_string_literal: true

module SilkenNet
  module LoadTest
    # = ===================================================================
    # 🔬 LorenzMicrobench — ІЗОЛЬОВАНИЙ pure-compute GVL-knee (red-team #7)
    # = ===================================================================
    # Тільки SilkenNet::Attractor.calculate_z_from_state у тісному циклі — БЕЗ
    # DB / Redis / логів / метрик / mutex'ів. Єдиний чесний доказ GVL-стелі:
    # на MRI 250-ітераційний Float-цикл ТРИМАЄ GVL, тож throughput має бути
    # ~плоским після 1 треда (додавання тредів не множить pure-Ruby CPU).
    #
    # Навіщо ОКРЕМО від drain_bench: у повному каскаді AES/DB/Redis ЗВІЛЬНЯЮТЬ
    # GVL і throughput росте з concurrency — але це масштабування IO-сегментів,
    # НЕ доказ, що compute GVL-bound. Якщо цей мікробенч плоский, а full-job ні,
    # висновок: сьогоднішнє вузьке місце — IO, не Lorenz (і це головний результат).
    module LorenzMicrobench
      module_function

      # Фіксовані фізично-валідні входи (homeostasis-band) — детерміновано,
      # той самий шлях, що гарячий per-packet compute_server_z.
      INPUTS = { x0: 1.0, y0: 1.0, z0: 1.0, temp: 20, acoustic: 3, delta_t: 30, vcap: 4000 }.freeze

      def run(iterations_per_thread: 2_000, thread_counts: [ 1, 5, 15 ])
        thread_counts.to_h { |n| [ n, measure(n, iterations_per_thread) ] }
      end

      # {threads, total_iters, throughput (iter/s), wall_s, gc_objects} для T тредів.
      # Warmup відкидається (YJIT/method-cache прогрів — red-team #8).
      def measure(threads, iters)
        warmup(iters / 10)
        GC.start
        gc_before = GC.stat(:total_allocated_objects)

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC) # монотонний, не wall (NTP)
        Array.new(threads) { Thread.new { spin(iters) } }.each(&:join)
        wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

        total = threads * iters
        {
          threads: threads,
          total_iters: total,
          throughput: (total / wall).round,
          wall_s: wall.round(4),
          gc_objects: GC.stat(:total_allocated_objects) - gc_before
        }
      end

      def spin(iters)
        i = INPUTS
        iters.times do
          SilkenNet::Attractor.calculate_z_from_state(
            i[:x0], i[:y0], i[:z0], i[:temp], i[:acoustic], i[:delta_t], i[:vcap]
          )
        end
      end

      def warmup(iters)
        spin([ iters, 1 ].max)
      end
    end
  end
end
