# frozen_string_literal: true

require "rails_helper"

RSpec.describe Web3CircuitBreaker do
  # Створюємо тестовий клас, що включає Circuit Breaker
  let(:test_class) do
    Class.new do
      include Web3CircuitBreaker

      def test_call(service_name, &block)
        with_circuit_breaker(service_name, &block)
      end
    end
  end
  let(:instance) { test_class.new }
  let(:service_name) { "test_service" }

  before do
    # Очищаємо кеш перед кожним тестом
    Rails.cache.delete("circuit_breaker:#{service_name}:failures")
    Rails.cache.delete("circuit_breaker:#{service_name}:opened_at")
  end

  describe "#with_circuit_breaker" do
    context "when circuit is closed (normal operation)" do
      it "executes the block and returns result" do
        result = instance.test_call(service_name) { "success" }
        expect(result).to eq("success")
      end

      it "resets failure count on success" do
        Rails.cache.write("circuit_breaker:#{service_name}:failures", 3)

        instance.test_call(service_name) { "success" }

        expect(Rails.cache.read("circuit_breaker:#{service_name}:failures")).to be_nil
      end
    end

    context "when transient errors accumulate" do
      it "records failures and opens circuit after threshold" do
        Web3CircuitBreaker::FAILURE_THRESHOLD.times do |i|
          expect {
            instance.test_call(service_name) { raise Errno::ECONNREFUSED, "Connection refused" }
          }.to raise_error(Errno::ECONNREFUSED)
        end

        # Circuit is now open — next call should be rejected immediately
        expect {
          instance.test_call(service_name) { "should not execute" }
        }.to raise_error(Web3CircuitBreaker::CircuitOpenError, /Circuit breaker OPEN/)
      end

      it "increments failure count for each error" do
        3.times do
          expect {
            instance.test_call(service_name) { raise Net::ReadTimeout, "read timeout" }
          }.to raise_error(Net::ReadTimeout)
        end

        count = Rails.cache.read("circuit_breaker:#{service_name}:failures").to_i
        expect(count).to eq(3)
      end
    end

    context "when circuit is open" do
      before do
        Rails.cache.write("circuit_breaker:#{service_name}:failures", Web3CircuitBreaker::FAILURE_THRESHOLD)
        Rails.cache.write("circuit_breaker:#{service_name}:opened_at", Time.current.to_f)
      end

      it "rejects requests immediately (fail-fast)" do
        expect {
          instance.test_call(service_name) { "should not execute" }
        }.to raise_error(Web3CircuitBreaker::CircuitOpenError)
      end

      it "does not execute the block" do
        block_called = false

        expect {
          instance.test_call(service_name) { block_called = true }
        }.to raise_error(Web3CircuitBreaker::CircuitOpenError)

        expect(block_called).to be false
      end
    end

    context "when circuit transitions to half-open (after timeout)" do
      before do
        Rails.cache.write("circuit_breaker:#{service_name}:failures", Web3CircuitBreaker::FAILURE_THRESHOLD)
        # Set opened_at to past the timeout
        Rails.cache.write(
          "circuit_breaker:#{service_name}:opened_at",
          (Time.current - Web3CircuitBreaker::OPEN_TIMEOUT - 1).to_f
        )
      end

      it "allows a probe request through" do
        result = instance.test_call(service_name) { "recovery" }
        expect(result).to eq("recovery")
      end

      it "resets circuit on successful probe" do
        instance.test_call(service_name) { "recovery" }

        expect(Rails.cache.read("circuit_breaker:#{service_name}:failures")).to be_nil
        expect(Rails.cache.read("circuit_breaker:#{service_name}:opened_at")).to be_nil
      end

      it "re-opens circuit if probe fails" do
        expect {
          instance.test_call(service_name) { raise Errno::ECONNRESET, "Connection reset" }
        }.to raise_error(Errno::ECONNRESET)

        # Circuit should remain open (failure recorded)
        failures = Rails.cache.read("circuit_breaker:#{service_name}:failures").to_i
        expect(failures).to be >= Web3CircuitBreaker::FAILURE_THRESHOLD
      end
    end

    context "with non-circuit-breaker errors" do
      it "does not count application errors as circuit failures" do
        expect {
          instance.test_call(service_name) { raise ArgumentError, "bad input" }
        }.to raise_error(ArgumentError)

        count = Rails.cache.read("circuit_breaker:#{service_name}:failures").to_i
        expect(count).to eq(0)
      end
    end

    context "with independent services" do
      it "maintains separate circuits per service" do
        Web3CircuitBreaker::FAILURE_THRESHOLD.times do
          expect {
            instance.test_call("service_a") { raise Errno::ECONNREFUSED }
          }.to raise_error(Errno::ECONNREFUSED)
        end

        # service_a is open, but service_b should still be closed
        expect {
          instance.test_call("service_a") { "a" }
        }.to raise_error(Web3CircuitBreaker::CircuitOpenError)

        result = instance.test_call("service_b") { "b works" }
        expect(result).to eq("b works")
      end
    end
  end
end
