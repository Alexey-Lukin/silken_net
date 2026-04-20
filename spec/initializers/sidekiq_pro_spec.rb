# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sidekiq Pro/Enterprise shims" do # rubocop:disable RSpec/DescribeClass
  describe "Sidekiq::Batch" do
    it "is defined" do
      expect(defined?(Sidekiq::Batch)).to be_truthy
    end

    describe "#initialize" do
      it "generates a unique bid" do
        batch = Sidekiq::Batch.new
        expect(batch.bid).to be_a(String)
        expect(batch.bid.length).to eq(16) # hex(8) = 16 chars
      end

      it "generates different bids for different batches" do
        bid1 = Sidekiq::Batch.new.bid
        bid2 = Sidekiq::Batch.new.bid
        expect(bid1).not_to eq(bid2)
      end
    end

    describe "#description" do
      it "supports setting and reading description" do
        batch = Sidekiq::Batch.new
        batch.description = "Test Batch"
        expect(batch.description).to eq("Test Batch")
      end
    end

    describe "#on" do
      it "registers success callbacks" do
        batch = Sidekiq::Batch.new
        batch.on(:success, "MyCallbackClass", cycle_id: "test")

        expect(batch.callbacks.size).to eq(1)
        expect(batch.callbacks.first[:event]).to eq(:success)
        expect(batch.callbacks.first[:klass]).to eq("MyCallbackClass")
        expect(batch.callbacks.first[:options]).to eq(cycle_id: "test")
      end

      it "registers multiple callbacks" do
        batch = Sidekiq::Batch.new
        batch.on(:success, "SuccessHandler")
        batch.on(:complete, "CompleteHandler")
        batch.on(:death, "DeathHandler")

        expect(batch.callbacks.size).to eq(3)
        expect(batch.callbacks.map { |c| c[:event] }).to eq(%i[success complete death])
      end

      it "converts string events to symbols" do
        batch = Sidekiq::Batch.new
        batch.on("success", "MyHandler")

        expect(batch.callbacks.first[:event]).to eq(:success)
      end
    end

    describe "#jobs" do
      it "yields the block" do
        batch = Sidekiq::Batch.new
        executed = false

        batch.jobs { executed = true }

        expect(executed).to be true
      end

      it "allows enqueueing workers inside the block" do
        batch = Sidekiq::Batch.new
        expect {
          batch.jobs do
            # Simulating worker enqueue
          end
        }.not_to raise_error
      end
    end

    describe "Sidekiq::Batch::Status" do
      it "stores bid" do
        status = Sidekiq::Batch::Status.new("abc123")
        expect(status.bid).to eq("abc123")
      end

      it "reports as complete" do
        status = Sidekiq::Batch::Status.new("test")
        expect(status.complete?).to be true
      end

      it "reports zero totals" do
        status = Sidekiq::Batch::Status.new("test")
        expect(status.total).to eq(0)
        expect(status.failures).to eq(0)
        expect(status.pending).to eq(0)
      end
    end
  end

  describe "Sidekiq::Limiter" do
    it "is defined" do
      expect(defined?(Sidekiq::Limiter)).to be_truthy
    end

    describe "::OverLimit" do
      it "is a StandardError" do
        expect(Sidekiq::Limiter::OverLimit.new).to be_a(StandardError)
      end
    end

    describe ".window" do
      it "returns a WindowLimiter" do
        limiter = Sidekiq::Limiter.window("test_limiter", 10, :second)
        expect(limiter).to be_a(Sidekiq::Limiter::WindowLimiter)
      end

      it "stores name, limit, and period" do
        limiter = Sidekiq::Limiter.window("rpc_limiter", 50, :minute)
        expect(limiter.name).to eq("rpc_limiter")
        expect(limiter.limit).to eq(50)
        expect(limiter.period).to eq(:minute)
      end
    end

    describe "WindowLimiter#within_limit" do
      it "yields the block without restriction in shim mode" do
        limiter = Sidekiq::Limiter.window("test", 1, :second)
        result = nil

        limiter.within_limit { result = "executed" }

        expect(result).to eq("executed")
      end

      it "returns the block's return value" do
        limiter = Sidekiq::Limiter.window("test", 1, :second)

        result = limiter.within_limit { 42 }

        expect(result).to eq(42)
      end

      it "allows unlimited calls in shim mode" do
        limiter = Sidekiq::Limiter.window("test", 1, :second)

        # Even though limit is 1, shim doesn't enforce
        expect {
          5.times { limiter.within_limit { "ok" } }
        }.not_to raise_error
      end
    end
  end
end
