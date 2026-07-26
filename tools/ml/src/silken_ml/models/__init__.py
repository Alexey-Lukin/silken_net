# SPDX-License-Identifier: AGPL-3.0-or-later
"""Model architecture for the baseline per-frame acoustic classifier.

Path B (docs/03_03 §4.3) — but the DEPLOYED ``Run_Inference`` contract is **per-frame**
(40 log-mel → 5 classes), NOT a spectrogram CNN. So the baseline is a TINY 2-layer MLP
over the 40 mel features, chosen UNDER the measured arena ceiling (docs/03_03 §6):

    Input(40) → Normalization(adapted) → Dense(hidden, relu) → Dense(5 logits)

The leading ``Normalization`` is the contract's "input normalization in the model"
(§3.4) — it is an affine transform that ``silken_ml.export`` **folds into the first
Dense** at INT8-export time, so the deployed graph is a plain ``FC → ReLU → FC`` (a
trivial integer forward pass; the device feeds raw log-mel). Output: 5 classes
(silence / wind / cavitation / chainsaw / fauna).
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ModelConfig:
    n_mels: int = 40
    hidden: int = 16
    n_classes: int = 5


def build_model(norm_mean, norm_var, cfg: ModelConfig | None = None):
    """Keras model with a fixed (deterministic) input Normalization from train stats."""
    import tensorflow as tf
    from tensorflow.keras import Model, layers

    cfg = cfg if cfg is not None else ModelConfig()

    inp = layers.Input(shape=(cfg.n_mels,), name="logmel")
    z = layers.Normalization(axis=-1, mean=norm_mean, variance=norm_var, name="norm")(inp)
    h = layers.Dense(cfg.hidden, activation="relu", name="fc1")(z)
    logits = layers.Dense(cfg.n_classes, name="logits")(h)
    return Model(inp, logits, name="silken_baseline_acoustic")
