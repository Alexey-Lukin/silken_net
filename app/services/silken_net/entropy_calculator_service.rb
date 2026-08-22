# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module SilkenNet
  # = ===================================================================
  # 🎲 ENTROPY CALCULATOR SERVICE (Shannon Entropy of Z-Value Distributions)
  # = ===================================================================
  # Обчислює нормалізовану ентропію Шеннона для масиву Z-значень атрактора Лоренца.
  #
  # Фізичний зміст:
  #   Здоровий ліс має різноманітні Z-значення (high entropy ≈ 1.0) — кожне дерево
  #   реагує індивідуально на мікросередовище (інсоляція, вологість ґрунту, температура).
  #   Лісовий стрес (посуха, хвороба, забруднення) гомогенізує відповіді дерев —
  #   Z-значення стають подібними (low entropy → 0.0).
  #
  # Чому Z-value, а не HRNG chaos_seed:
  #   chaos_seed (HRNG) НЕ передається у 21-байтному LoRa-пакеті (03_01, Phase 2).
  #   Backend використовує z_value як проксі для ентропійного аналізу кластера.
  #   Метод і пороги — дім 04_02 (ClusterEntropyAnalyzerWorker); партнер-верифікація
  #   акустики й сигналів — 00_02 §1.2. Тут доти стояв task-номер розчиненого модуля.
  #
  # Математика:
  #   H = -Σ p(x) × log₂(p(x))
  #   H_norm = H / log₂(num_bins)  ∈ [0.0, 1.0]
  #
  # Використання:
  #   SilkenNet::EntropyCalculatorService.call([29.1, 28.5, 30.2, 27.8, ...])
  #   => 0.87  (висока ентропія — гомеостаз)
  #
  class EntropyCalculatorService < ApplicationService
    # Мінімальна кількість точок даних для статистично значущого аналізу.
    # При менш ніж 30 значеннях розподіл нестабільний — повертаємо nil.
    MIN_SAMPLE_SIZE = 30

    # Кількість бінів для гістограми Z-значень.
    # Z ∈ [CRITICAL_Z_MIN=2.0, CRITICAL_Z_MAX=45.0] → діапазон ~43 одиниці.
    # 20 бінів дає ширину ~2.15 — достатня роздільна здатність для виявлення
    # кластеризації Z-значень, але не надто гранулярно для типових N=100-1000.
    NUM_BINS = 20

    # Фіксовані межі бінування — відповідають Lorenz Z-value homeostasis zone.
    # Використовуємо ФІКСОВАНИЙ діапазон (а не adaptive min/max) для коректного
    # порівняння ентропії між кластерами та між часовими вікнами.
    # Якщо всі Z зосереджені в 1-2 бінах із 20 — ентропія низька (стрес).
    # Якщо Z розподілені рівномірно по бінах — ентропія висока (гомеостаз).
    BIN_RANGE_MIN = 2.0   # SilkenNet::BioContract::CRITICAL_Z_MIN
    BIN_RANGE_MAX = 45.0  # SilkenNet::BioContract::CRITICAL_Z_MAX

    def initialize(z_values)
      @z_values = Array(z_values).select { |v| v.is_a?(Numeric) && v.finite? }
    end

    def perform
      return nil if @z_values.size < MIN_SAMPLE_SIZE

      calculate_normalized_shannon_entropy
    end

    private

    # Нормалізована ентропія Шеннона для дискретизованих Z-значень.
    # Використовує ФІКСОВАНЕ бінування по діапазону [BIN_RANGE_MIN, BIN_RANGE_MAX].
    def calculate_normalized_shannon_entropy
      range = BIN_RANGE_MAX - BIN_RANGE_MIN
      bin_width = range / NUM_BINS.to_f

      # Підрахунок частот у кожному біні
      frequencies = Array.new(NUM_BINS, 0)
      total = @z_values.size.to_f

      @z_values.each do |val|
        # Значення за межами діапазону потрапляють у крайні біни
        clamped = val.clamp(BIN_RANGE_MIN, BIN_RANGE_MAX)
        bin_index = ((clamped - BIN_RANGE_MIN) / bin_width).floor
        bin_index = NUM_BINS - 1 if bin_index >= NUM_BINS
        frequencies[bin_index] += 1
      end

      # Ентропія Шеннона: H = -Σ p(x) × log₂(p(x))
      # Ігноруємо порожні біни (p=0 → 0×log(0) = 0 за конвенцією)
      entropy = 0.0
      frequencies.each do |count|
        next if count.zero?

        probability = count / total
        entropy -= probability * Math.log2(probability)
      end

      # Нормалізація: H_norm = H / H_max, де H_max = log₂(NUM_BINS).
      # Це дає 1.0 при ідеально рівномірному розподілі по ВСІХ бінах.
      # NUM_BINS=20 → max_entropy = log2(20) ≈ 4.32, ніколи 0; guard захищає ділення нижче
      # від NUM_BINS=1 misconfig (div-by-zero) — dead за константою (§B.4 leave).
      max_entropy = Math.log2(NUM_BINS)
      return 0.0 if max_entropy.zero?

      normalized = entropy / max_entropy
      normalized.clamp(0.0, 1.0).round(4)
    end
  end
end
