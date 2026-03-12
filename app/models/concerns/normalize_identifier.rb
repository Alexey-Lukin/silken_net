# frozen_string_literal: true

# = ===================================================================
# 🔧 NORMALIZE IDENTIFIER (Shared Device UID/DID Normalization)
# = ===================================================================
# Уніфікована нормалізація апаратних ідентифікаторів для всіх IoT-пристроїв:
# - Tree.did      (SNET-XXXXXXXX)
# - Gateway.uid   (SNET-Q-XXXXXXXX)
# - HardwareKey.device_uid (обидва формати)
#
# Нормалізація: strip + upcase (STM32 UID → uppercase hex)
#
# Використання:
#   class Tree < ApplicationRecord
#     include NormalizeIdentifier
#     normalize_identifier :did
#   end
module NormalizeIdentifier
  extend ActiveSupport::Concern

  class_methods do
    # Застосовує Rails `normalizes` для вказаного атрибута.
    # Виконує strip + upcase для сумісності з апаратним форматом STM32.
    #
    # @param attribute [Symbol] назва поля для нормалізації (:did, :uid, :device_uid)
    def normalize_identifier(attribute)
      normalizes attribute, with: ->(value) { value.to_s.strip.upcase }
    end
  end
end
