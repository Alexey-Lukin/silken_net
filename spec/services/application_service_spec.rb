# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationService do
  # Тестовий сервіс для перевірки базового контракту
  let(:test_service_class) do
    Class.new(described_class) do
      attr_reader :input

      def initialize(input)
        @input = input
      end

      def perform
        "processed:#{@input}"
      end
    end
  end

  describe ".call" do
    it "delegates to new(...).perform" do
      result = test_service_class.call("hello")
      expect(result).to eq("processed:hello")
    end

    it "passes multiple arguments" do
      multi_arg_class = Class.new(described_class) do
        def initialize(a, b, key: nil)
          @a = a
          @b = b
          @key = key
        end

        def perform
          "#{@a}+#{@b}+#{@key}"
        end
      end

      expect(multi_arg_class.call(1, 2, key: "x")).to eq("1+2+x")
    end

    it "works with no arguments" do
      no_arg_class = Class.new(described_class) do
        def perform
          42
        end
      end

      expect(no_arg_class.call).to eq(42)
    end
  end
end
