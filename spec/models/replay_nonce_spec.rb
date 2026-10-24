# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [SEC.39, ⚖️ founder 2026-10-24] Атомарний анти-повтор у Postgres. Дві діри Solid Cache, проти
# яких його збудовано: (1) два конкурентні перші записи обидва вигравали; (2) збій сховища
# повертав `false`, і сайт читав його як ПОВТОР.
RSpec.describe ReplayNonce do
  describe ".claim!" do
    it "lets the first claim win and refuses a live one" do
      expect(described_class.claim!(scope: "panic", digest: "k", ttl: 1.hour)).to be true
      expect(described_class.claim!(scope: "panic", digest: "k", ttl: 1.hour)).to be false
    end

    it "keys the claim by scope — the same digest in another scope is fresh" do
      described_class.claim!(scope: "panic", digest: "k", ttl: 1.hour)

      expect(described_class.claim!(scope: "device_event", digest: "k", ttl: 1.hour)).to be true
    end

    it "re-claims an expired key with the same atomic statement — correctness needs no purge" do
      described_class.claim!(scope: "panic", digest: "k", owner: "old", ttl: 1.hour)

      travel 2.hours do
        expect(described_class.claim!(scope: "panic", digest: "k", owner: "new", ttl: 1.hour)).to be true
        expect(described_class.owner_of(scope: "panic", digest: "k")).to eq("new")
      end
    end

    # 🔴 Друга діра: збій сховища мусить долетіти до сайту, а не перетворитись на «повтор».
    it "does not swallow a database error" do
      allow(described_class.connection).to receive(:select_value).and_raise(ActiveRecord::StatementTimeout)

      expect { described_class.claim!(scope: "panic", digest: "k", ttl: 1.hour) }
        .to raise_error(ActiveRecord::StatementTimeout)
    end
  end

  describe ".owner_of / .finalize!" do
    it "reads the live owner and replaces it with the terminal marker" do
      described_class.claim!(scope: "device_event", digest: "k", owner: "jid-1", ttl: 1.hour)
      expect(described_class.owner_of(scope: "device_event", digest: "k")).to eq("jid-1")

      described_class.finalize!(scope: "device_event", digest: "k", owner: "done", ttl: 1.hour)
      expect(described_class.owner_of(scope: "device_event", digest: "k")).to eq("done")
    end

    # 🔴 Ключ буває взято поза таблицею (Redis-шлях QATT, що впав перед фіналізацією), і тоді
    # рядка немає: голий UPDATE мовчки не писав би done, і повтор під аварією пройшов би фолбеком.
    it "writes the terminal marker even when no claim row exists" do
      described_class.finalize!(scope: "qatt_fallback", digest: "k", owner: "done", ttl: 1.hour)

      expect(described_class.claim!(scope: "qatt_fallback", digest: "k", owner: "jid-2", ttl: 1.hour)).to be false
      expect(described_class.owner_of(scope: "qatt_fallback", digest: "k")).to eq("done")
    end

    it "does not report an owner for an expired key" do
      described_class.claim!(scope: "device_event", digest: "k", owner: "jid-1", ttl: 1.hour)

      travel(2.hours) { expect(described_class.owner_of(scope: "device_event", digest: "k")).to be_nil }
    end
  end

  # 🔴 Перша діра — і пін на неї мусить іти через СПРАВЖНІ окремі зʼєднання. Транзакційні
  # фікстури ділять ОДНЕ зʼєднання між потоками (`lock_threads`), тож «конкурентні» claim
  # виконались би послідовно, і пін був би зеленим на будь-якій реалізації. Тому без
  # транзакції — і з прибиранням за собою.
  context "with two concurrent first writers on real connections" do
    self.use_transactional_tests = false

    after { described_class.where(scope: "spec_race").delete_all }

    it "admits exactly one of them" do
      5.times do |round|
        barrier = Concurrent::CyclicBarrier.new(2)
        results = Array.new(2) do
          Thread.new do
            described_class.connection_pool.with_connection do
              barrier.wait(5)
              described_class.claim!(scope: "spec_race", digest: "k#{round}", ttl: 1.hour)
            end
          end
        end.map(&:value)

        expect(results.count(true)).to eq(1), "round #{round}: #{results.inspect}"
      end
    end
  end
end
