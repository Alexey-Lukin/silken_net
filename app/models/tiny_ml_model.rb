# frozen_string_literal: true

class TinyMlModel < ApplicationRecord
  # Кластери або дерева, які зараз використовують цю версію нейромережі
  has_many :trees, dependent: :nullify

  # version: рядок (напр. "v2.1.0-bark-beetle")
  # target_species: посилання на TreeFamily (для корекції акустичних сигналів)
  belongs_to :tree_family, optional: true
  
  # binary_weights_payload: двійковий блок (ваги моделі TFLite Micro)
  validates :version, presence: true, uniqueness: true
  validates :binary_weights_payload, presence: true

  # Розмір у байтах для розбивки на чанки при радіопередачі
  def payload_size
    binary_weights_payload.bytesize
  end

  # [НОВЕ]: Перевірка цілісності перед відправкою у ліс
  def checksum
    Digest::SHA256.hexdigest(binary_weights_payload)
  end
end
