# frozen_string_literal: true

require "socket"

module SilkenNet
  module LoadTest
    # = ===================================================================
    # 🌊 CoapFlood — intake UDP-навантаження на CoAP-listener (INF.23)
    # = ===================================================================
    # Open-model fire-and-forget (Королева шле незалежно від ACK — реалістично,
    # і CO у сенсі Gil Tene тут не діє). Червоні прапори (red-team #4/#5),
    # вбудовані як дисципліна, а не опції:
    #
    #  • pre-generate ВСІ датаграми в пам'ять ДО таймера + persistent socket
    #    на воркера → hot-loop = чистий socket.send (не CoapClient.put, що
    #    робить UDPSocket.new + ACK-wait = closed-loop churn).
    #  • offered_rps (ціль) окремо від achieved_rps (реально надіслано) —
    #    плато дійсне лише якщо offered > achieved (інакше зміряв генератор).
    #  • forked-scaling: більше воркерів → якщо achieved росте лінійно, впирався
    #    генератор; якщо плато — вузьке місце нижче (listener/kernel).
    #  • kernel UDP-drop лічильник (before/after) — авторитетний, бо демон
    #    ковтає Redis-enqueue-fail без метрики (PERF-3), а loopback ховає
    #    NIC-ring-drop (⚠️ Darwin recvspace ~42KB → knee = артефакт, не стеля;
    #    intake-число НЕ переноситься на Linux — re-run на staging).
    #  • monotonic MID (не random) — birthday-колізії дали б фейкові «дропи».
    #
    # Split-registry (red-team #8): drop-rate = offered − listener'ів
    # COAP_PACKETS{enqueued}; знімай ту метрику з ПРОЦЕСУ listener'а (coap:9395),
    # не з web. Тут гарнес рахує лише offered/achieved на своєму боці.
    module CoapFlood
      module_function

      POOL_SIZE = 1024

      # Pre-generated пул валідних CoAP CON PUT з монотонним MID (циклиться).
      def pregenerate(gateway_uid, payload_bytes)
        payload = TelemetryBatchFactory.random_payload(payload_bytes)
        (1..POOL_SIZE).map do |mid|
          CoapClient.build_put(message_id: mid, path: "/telemetry/batch/#{gateway_uid}", payload: payload)
        end
      end

      # Один воркер: persistent socket, темп offered_rps, тривалість duration_s.
      # Повертає {sent:, elapsed_s:}.
      def flood_worker(host, port, datagrams, offered_rps, duration_s)
        socket   = UDPSocket.new
        interval = 1.0 / offered_rps
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration_s
        sent     = 0
        i        = 0

        while (now = Process.clock_gettime(Process::CLOCK_MONOTONIC)) < deadline
          socket.send(datagrams[i % datagrams.size], 0, host, port)
          sent += 1
          i += 1
          # Pace до intended-send-time (гэпи від sender-stall не приховуються).
          nxt = now + interval
          slack = nxt - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          sleep(slack) if slack.positive?
        end
        sent
      ensure
        socket&.close
      end

      # Флуд: N воркерів × offered_rps кожен. Kernel-drop delta + SO_RCVBUF-нота.
      def run(host:, port: 5683, gateway_uid:, offered_rps:, duration_s:, payload_bytes: 800, workers: 1)
        raise ArgumentError, "offered_rps має бути > 0" unless offered_rps.positive?

        datagrams = pregenerate(gateway_uid, payload_bytes)
        per_worker = offered_rps.to_f / workers
        drops_before = kernel_udp_drops

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        sent = Array.new(workers) do
          Thread.new { flood_worker(host, port, datagrams, per_worker, duration_s) }
        end.map(&:value).sum
        wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
        {
          host: "#{host}:#{port}", workers: workers,
          offered_rps: offered_rps, achieved_rps: (sent / wall).round(1),
          sent: sent, duration_s: wall.round(3),
          kernel_udp_drops_delta: drops_delta(drops_before),
          caveat: "loopback ховає NIC-ring-drop (Darwin recvspace); intake-число НЕ переноситься на Linux — re-run staging. drop-rate = offered − listener COAP_PACKETS{enqueued} (split-registry)."
        }
      end

      # Авторитетний kernel-лічильник UDP recv-buffer drop'ів (best-effort, платформа).
      def kernel_udp_drops
        case RbConfig::CONFIG["host_os"]
        when /darwin/
          out = `netstat -s -p udp 2>/dev/null`
          out[/(\d+) dropped due to full socket buffers/, 1]&.to_i
        when /linux/
          parse_linux_udp_rcvbuf_errors(File.read("/proc/net/snmp"))
        end
      rescue StandardError
        nil
      end

      def parse_linux_udp_rcvbuf_errors(snmp)
        return nil unless snmp

        keys = snmp.lines.grep(/^Udp:\s+[A-Z]/).first&.split&.drop(1)
        vals = snmp.lines.grep(/^Udp:\s+\d/).first&.split&.drop(1)&.map(&:to_i)
        return nil unless keys && vals

        idx = keys.index("RcvbufErrors")
        idx ? vals[idx] : nil
      end

      def drops_delta(before)
        after = kernel_udp_drops
        return nil if before.nil? || after.nil?

        after - before
      end
    end
  end
end
