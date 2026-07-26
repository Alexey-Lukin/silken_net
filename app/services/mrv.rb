# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# MRV-домен (ARCH.12/MRV.1): Merkle-lineage примітиви credit→measurements.
module Mrv
  # GRACE-лаг верхньої межі вікон телеметрія-листя (тижневий якір + mint-lineage):
  # рядок, що комітиться під час снапшота/вибірки, вже має created_at нижче за «now» —
  # без лагу він випав би з поточного вікна і назавжди з усіх наступних (вікна
  # ланцюжаться). Історичні вікна від значення НЕ залежать — межі персистуються.
  WINDOW_GRACE = 5.minutes
end
