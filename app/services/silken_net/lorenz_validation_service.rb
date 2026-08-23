# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module SilkenNet
  # [Lorenz de-risk / 05_05 §8] Ground-truth validation harness.
  # ⚠️ Цей реф двічі пережив перенумерацію з ХИБНОЮ ціллю. Народився він у
  # розчиненому нині модулі 08, у доці про кібернетичну й математичну валідацію,
  # де секція з тим самим номером справді була про Z↔health. Модуль розчинили,
  # номер перезаселили реєстром ВНЗ — і та сама секція стала медакадемією.
  # Адреса лишилась валідною при підміненому змісті: резолвер такого не бачить
  # за побудовою, бо питає лише «чи існує», ніколи «чи про те саме».
  # (Координати навмисно прозою — цитата мертвого номера сама стає мертвим рефом.)
  #
  # Push-button correlation analysis for the "Lorenz Z ↔ tree health" hypothesis,
  # to be run once ЧНУ collects paired (telemetry, ground-truth) observations.
  #
  # PURE / READ-ONLY: every method is a pure function over the data passed in —
  # no DB reads/writes, no slashing side-effects, no global state. Safe to run
  # anywhere (rake task, console, CI) without touching production records.
  #
  # Primary questions it answers (05_05 §8):
  #   1. Does `stress_index` track ground-truth decline?         → spearman
  #   2. Does Z add predictive value OVER direct signals (sap)?   → report[:z_incremental_over_sap]
  #   3. Does device bio_status agree with expert labels?         → cohens_kappa
  #   4. Is the slashing detector safe (low false positives)?     → binary_metrics[:fpr]
  module LorenzValidationService
    module_function

    # Spearman rank correlation in [-1, 1]. Robust to non-linear monotonic
    # relationships — the right tool for "does higher stress_index mean sicker
    # tree" without assuming linearity. Ties resolved via average ranks.
    def spearman(xs, ys)
      pearson(ranks(xs), ranks(ys))
    end

    # Pearson (linear) correlation in [-1, 1]. 0.0 for degenerate input
    # (empty, length mismatch, or zero variance) — never raises.
    def pearson(xs, ys)
      n = xs.size
      return 0.0 if n.zero? || n != ys.size

      mean_x = xs.sum.to_f / n
      mean_y = ys.sum.to_f / n
      cov = var_x = var_y = 0.0
      xs.each_index do |i|
        dx = xs[i].to_f - mean_x
        dy = ys[i].to_f - mean_y
        cov += dx * dy
        var_x += dx * dx
        var_y += dy * dy
      end

      denom = Math.sqrt(var_x * var_y)
      denom.zero? ? 0.0 : (cov / denom).clamp(-1.0, 1.0)
    end

    # Cohen's κ — chance-corrected agreement between two categorical raters
    # (e.g. device-reported bio_status vs expert health label). 1.0 = perfect,
    # 0.0 = chance-level, <0 = worse than chance.
    def cohens_kappa(rater_a, rater_b)
      n = rater_a.size
      return 0.0 if n.zero? || n != rater_b.size

      observed = rater_a.each_index.count { |i| rater_a[i] == rater_b[i] }.to_f / n
      labels = (rater_a + rater_b).uniq
      expected = labels.sum do |label|
        (rater_a.count(label).to_f / n) * (rater_b.count(label).to_f / n)
      end

      return 1.0 if (1.0 - expected).abs < Float::EPSILON # single label → perfect by construction

      ((observed - expected) / (1.0 - expected)).round(4)
    end

    # Confusion matrix + rates for a binary stress detector. `predicted` and
    # `actual` are arrays of truthy/falsy. FPR is the slashing-safety metric:
    # the rate of healthy trees wrongly flagged as stressed (→ false slashing).
    def binary_metrics(predicted, actual)
      tp = fp = tn = fn = 0
      predicted.each_index do |i|
        p = predicted[i] ? true : false
        a = actual[i] ? true : false
        if p && a then tp += 1
        elsif p then fp += 1
        elsif a then fn += 1
        else tn += 1
        end
      end

      {
        tp: tp, fp: fp, tn: tn, fn: fn,
        fpr: rate(fp, fp + tn),       # false-positive rate — slashing safety
        tpr: rate(tp, tp + fn),       # recall / sensitivity
        precision: rate(tp, tp + fp)
      }
    end

    # Top-level report over paired samples. Each sample is a Hash with at least
    # :stress_index and :ground_truth_decline (higher = sicker). If :z_value and
    # :sap_flow are present, also reports the *incremental* predictive value of Z
    # over the direct physiological signal — the core de-risk question: if Z adds
    # ~nothing over sap_flow, demote Z to DCI-only (05_05 §8).
    def report(samples)
      stress = samples.map { |s| s[:stress_index].to_f }
      decline = samples.map { |s| s[:ground_truth_decline].to_f }
      out = { n: samples.size, spearman_stress_vs_decline: round(spearman(stress, decline)) }

      first = samples.first
      if first&.key?(:z_value) && first.key?(:sap_flow)
        z = samples.map { |s| s[:z_value].to_f }
        sap = samples.map { |s| s[:sap_flow].to_f }
        z_rho = spearman(z, decline)
        sap_rho = spearman(sap, decline)
        out[:spearman_z_vs_decline] = round(z_rho)
        out[:spearman_sap_vs_decline] = round(sap_rho)
        out[:z_incremental_over_sap] = round(z_rho.abs - sap_rho.abs)
      end

      out
    end

    # ── helpers ──────────────────────────────────────────────────────────
    def ranks(arr)
      indexed = arr.each_with_index.sort_by { |value, _| value.to_f }
      out = Array.new(arr.size)
      i = 0
      while i < indexed.size
        j = i
        # rubocop:disable Lint/FloatComparison -- ТОЧНА рівність тут і є предметом:
        # це виявлення ЗБІГІВ у рангуванні Спірмена. Epsilon-порівняння злило б у
        # звʼязку різні-але-близькі значення, тобто зіпсувало б сам ранг.
        j += 1 while j < indexed.size && indexed[j][0].to_f == indexed[i][0].to_f
        # rubocop:enable Lint/FloatComparison
        avg_rank = ((i + 1) + j) / 2.0 # 1-based ranks (i+1)..j averaged over ties
        (i...j).each { |k| out[indexed[k][1]] = avg_rank }
        i = j
      end
      out
    end

    def rate(numerator, denominator)
      denominator.zero? ? 0.0 : (numerator.to_f / denominator).round(4)
    end

    def round(value)
      value.round(4)
    end
  end
end
