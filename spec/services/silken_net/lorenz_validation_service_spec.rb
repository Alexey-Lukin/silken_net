# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# [Lorenz de-risk / 05_05 §8] Unit coverage for the ground-truth validation harness.
# Pure functions — no DB. Verifies the stats are correct so the eventual ЧНУ
# analysis (Z↔health) can be trusted.
RSpec.describe SilkenNet::LorenzValidationService do
  describe ".pearson" do
    it "is +1.0 for a perfect positive linear relationship" do
      expect(described_class.pearson([ 1, 2, 3, 4 ], [ 2, 4, 6, 8 ])).to be_within(1e-9).of(1.0)
    end

    it "is -1.0 for a perfect negative linear relationship" do
      expect(described_class.pearson([ 1, 2, 3, 4 ], [ 8, 6, 4, 2 ])).to be_within(1e-9).of(-1.0)
    end

    it "is 0.0 for degenerate input (zero variance, empty, length mismatch)" do
      expect(described_class.pearson([ 5, 5, 5 ], [ 1, 2, 3 ])).to eq(0.0)
      expect(described_class.pearson([], [])).to eq(0.0)
      expect(described_class.pearson([ 1, 2 ], [ 1, 2, 3 ])).to eq(0.0)
    end
  end

  describe ".spearman" do
    it "is +1.0 for a monotonic (non-linear) increasing relationship" do
      expect(described_class.spearman([ 1, 2, 3, 4 ], [ 1, 4, 9, 16 ])).to be_within(1e-9).of(1.0)
    end

    it "is -1.0 for monotonic decreasing" do
      expect(described_class.spearman([ 1, 2, 3, 4 ], [ 10, 7, 5, 1 ])).to be_within(1e-9).of(-1.0)
    end

    it "stays finite and bounded with tied ranks" do
      expect(described_class.spearman([ 1, 2, 2, 3 ], [ 1, 2, 3, 4 ])).to be_between(-1.0, 1.0)
    end
  end

  describe ".cohens_kappa" do
    it "is 1.0 for identical raters across multiple labels" do
      a = %i[homeostasis stress anomaly homeostasis]
      expect(described_class.cohens_kappa(a, a.dup)).to eq(1.0)
    end

    it "is below 1.0 when raters disagree" do
      a = %i[homeostasis stress anomaly homeostasis]
      b = %i[homeostasis homeostasis anomaly stress]
      expect(described_class.cohens_kappa(a, b)).to be < 1.0
    end

    it "returns 1.0 for a single shared label (degenerate, no chance to disagree)" do
      expect(described_class.cohens_kappa(%i[x x], %i[x x])).to eq(1.0)
    end

    it "returns 0.0 for empty rater arrays" do
      expect(described_class.cohens_kappa([], [])).to eq(0.0)
    end

    it "returns 0.0 when rater sizes mismatch (refuses to compute)" do
      expect(described_class.cohens_kappa([ :a, :b ], [ :a ])).to eq(0.0)
    end
  end

  describe ".binary_metrics" do
    it "computes the confusion matrix + FPR/TPR/precision" do
      predicted = [ true, true, false, false, true ]
      actual    = [ true, false, false, true, false ]
      m = described_class.binary_metrics(predicted, actual)

      expect(m).to include(tp: 1, fp: 2, tn: 1, fn: 1)
      expect(m[:fpr]).to be_within(1e-4).of(2.0 / 3.0) # fp / (fp + tn) — slashing safety
      expect(m[:tpr]).to be_within(1e-4).of(0.5)        # tp / (tp + fn)
    end

    it "returns 0.0 rates when the denominator is zero (all-negative or all-positive ground truth)" do
      m = described_class.binary_metrics([ true, false ], [ false, false ])
      expect(m[:tpr]).to eq(0.0)
      m2 = described_class.binary_metrics([ true, false ], [ true, true ])
      expect(m2[:fpr]).to eq(0.0)
    end
  end

  describe ".report" do
    it "reports strong correlation when stress_index tracks ground-truth decline" do
      samples = (1..10).map { |i| { stress_index: i / 10.0, ground_truth_decline: i.to_f } }
      r = described_class.report(samples)

      expect(r[:n]).to eq(10)
      expect(r[:spearman_stress_vs_decline]).to be_within(1e-6).of(1.0)
    end

    it "reports each signal's own marginal rho against decline" do
      # sap_flow falls as decline rises (perfect inverse monotonic) → -1.0;
      # Z is constant noise → zero variance → 0.0. Both are DESCRIPTIVE: the
      # harness derives no incremental figure from the pair (05_05 §8.1).
      samples = [
        { stress_index: 0.1, ground_truth_decline: 1, z_value: 5, sap_flow: 9 },
        { stress_index: 0.5, ground_truth_decline: 5, z_value: 5, sap_flow: 5 },
        { stress_index: 0.9, ground_truth_decline: 9, z_value: 5, sap_flow: 1 }
      ]
      r = described_class.report(samples)

      expect(r[:spearman_sap_vs_decline]).to be_within(1e-6).of(-1.0)
      expect(r[:spearman_z_vs_decline]).to eq(0.0)
    end

    it "omits the z_vs_sap block for samples that carry only stress_index" do
      samples = [ { stress_index: 0.1, ground_truth_decline: 1 } ]
      r = described_class.report(samples)

      expect(r).not_to have_key(:spearman_z_vs_decline)
      expect(r).not_to have_key(:spearman_sap_vs_decline)
    end

    it "omits the z_vs_sap block for empty samples (safe-navigation on first)" do
      r = described_class.report([])
      expect(r[:n]).to eq(0)
      expect(r).not_to have_key(:spearman_z_vs_decline)
    end
  end
end
