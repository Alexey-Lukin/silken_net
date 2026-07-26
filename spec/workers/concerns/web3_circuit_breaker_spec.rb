# SPDX-License-Identifier: AGPL-3.0-or-later
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

      it "still fail-fasts when the rejection metric constant is undefined (defined?-guard else)" do
        hide_const("SilkenNet::Metrics::CIRCUIT_BREAKER_REJECTIONS")

        expect {
          instance.test_call(service_name) { "should not execute" }
        }.to raise_error(Web3CircuitBreaker::CircuitOpenError)
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

    context "with wrapped errors (transient_cause?)" do
      it "counts failures for custom errors with transient root cause" do
        custom_error = Class.new(StandardError)

        Web3CircuitBreaker::FAILURE_THRESHOLD.times do
          begin
            raise Errno::ECONNREFUSED, "connection refused"
          rescue Errno::ECONNREFUSED
            expect {
              instance.test_call(service_name) { raise custom_error, "dispatch failed" }
            }.to raise_error(custom_error)
          end
        end

        count = Rails.cache.read("circuit_breaker:#{service_name}:failures").to_i
        expect(count).to eq(Web3CircuitBreaker::FAILURE_THRESHOLD)
      end

      it "does not count failures for custom errors without transient cause" do
        custom_error = Class.new(StandardError)

        expect {
          instance.test_call(service_name) { raise custom_error, "validation error" }
        }.to raise_error(custom_error)

        count = Rails.cache.read("circuit_breaker:#{service_name}:failures").to_i
        expect(count).to eq(0)
      end

      it "detects transient cause in deeply nested exceptions" do
        wrapper_error = Class.new(StandardError)

        # Simulate a wrapper_error whose cause is an Errno::ECONNREFUSED
        error_with_cause = nil
        begin
          begin
            raise Errno::ECONNREFUSED, "connection refused"
          rescue Errno::ECONNREFUSED
            raise wrapper_error, "outer wrap"
          end
        rescue wrapper_error => e
          error_with_cause = e
        end

        expect {
          instance.test_call(service_name) { raise error_with_cause }
        }.to raise_error(wrapper_error)

        count = Rails.cache.read("circuit_breaker:#{service_name}:failures").to_i
        expect(count).to eq(1)
      end
    end

    context "with all CIRCUIT_BREAKER_ERRORS types" do
      Web3CircuitBreaker::CIRCUIT_BREAKER_ERRORS.each do |error_class|
        it "counts #{error_class.name} as a circuit breaker failure" do
          # Some error classes require specific constructor arguments
          error_instance = begin
            error_class.new("test #{error_class}")
          rescue ArgumentError
            error_class.new("test", "#{error_class}")
          end

          expect {
            instance.test_call(service_name) { raise error_instance }
          }.to raise_error(error_class)

          count = Rails.cache.read("circuit_breaker:#{service_name}:failures").to_i
          expect(count).to eq(1)
        end
      end
    end
  end

  describe "#reset_circuit!" do
    it "deletes both failure count and opened_at keys" do
      # Set failures below threshold so circuit stays closed
      Rails.cache.write("circuit_breaker:#{service_name}:failures", 3)
      Rails.cache.write("circuit_breaker:#{service_name}:opened_at", Time.current.to_f)

      instance.test_call(service_name) { "success" }

      expect(Rails.cache.read("circuit_breaker:#{service_name}:failures")).to be_nil
      expect(Rails.cache.read("circuit_breaker:#{service_name}:opened_at")).to be_nil
    end
  end

  describe "#remaining_open_seconds" do
    it "returns 0 when circuit has no opened_at" do
      remaining = instance.send(:remaining_open_seconds, service_name)
      expect(remaining).to eq(0)
    end

    it "returns positive seconds when circuit was recently opened" do
      Rails.cache.write("circuit_breaker:#{service_name}:opened_at", Time.current.to_f)

      remaining = instance.send(:remaining_open_seconds, service_name)
      expect(remaining).to be > 0
      expect(remaining).to be <= Web3CircuitBreaker::OPEN_TIMEOUT
    end

    it "returns 0 when timeout has elapsed" do
      Rails.cache.write(
        "circuit_breaker:#{service_name}:opened_at",
        (Time.current - Web3CircuitBreaker::OPEN_TIMEOUT - 10).to_f
      )

      remaining = instance.send(:remaining_open_seconds, service_name)
      expect(remaining).to eq(0)
    end
  end

  describe "#transient_cause?" do
    it "returns false when error has no cause" do
      error = StandardError.new("no cause")
      result = instance.send(:transient_cause?, error)
      expect(result).to be false
    end

    it "returns true when direct cause is a transient error" do
      begin
        raise Errno::ECONNREFUSED, "connection refused"
      rescue Errno::ECONNREFUSED
        error = StandardError.new("wrapped")
        begin
          raise error
        rescue StandardError => e
          result = instance.send(:transient_cause?, e)
          expect(result).to be true
        end
      end
    end
  end

  describe "#circuit_state" do
    it "returns :closed when failures are below threshold" do
      Rails.cache.write("circuit_breaker:#{service_name}:failures", 3)

      state = instance.send(:circuit_state, service_name)
      expect(state).to eq(:closed)
    end

    it "returns :open when failures >= threshold and timeout not elapsed" do
      Rails.cache.write("circuit_breaker:#{service_name}:failures", Web3CircuitBreaker::FAILURE_THRESHOLD)
      Rails.cache.write("circuit_breaker:#{service_name}:opened_at", Time.current.to_f)

      state = instance.send(:circuit_state, service_name)
      expect(state).to eq(:open)
    end

    it "returns :half_open when failures >= threshold and timeout elapsed" do
      Rails.cache.write("circuit_breaker:#{service_name}:failures", Web3CircuitBreaker::FAILURE_THRESHOLD)
      Rails.cache.write(
        "circuit_breaker:#{service_name}:opened_at",
        (Time.current - Web3CircuitBreaker::OPEN_TIMEOUT - 1).to_f
      )

      state = instance.send(:circuit_state, service_name)
      expect(state).to eq(:half_open)
    end

    it "returns :closed when failures below threshold even if opened_at exists" do
      Rails.cache.write("circuit_breaker:#{service_name}:failures", 2)
      Rails.cache.write("circuit_breaker:#{service_name}:opened_at", Time.current.to_f)

      state = instance.send(:circuit_state, service_name)
      expect(state).to eq(:closed)
    end
  end

  describe "#record_failure!" do
    it "increments failure count" do
      instance.send(:record_failure!, service_name)
      expect(Rails.cache.read("circuit_breaker:#{service_name}:failures").to_i).to eq(1)

      instance.send(:record_failure!, service_name)
      expect(Rails.cache.read("circuit_breaker:#{service_name}:failures").to_i).to eq(2)
    end

    it "writes opened_at when reaching threshold" do
      (Web3CircuitBreaker::FAILURE_THRESHOLD - 1).times do
        instance.send(:record_failure!, service_name)
      end

      expect(Rails.cache.read("circuit_breaker:#{service_name}:opened_at")).to be_nil

      instance.send(:record_failure!, service_name)

      expect(Rails.cache.read("circuit_breaker:#{service_name}:opened_at")).to be_present
    end
  end
end
