# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [UI.7] Спільний дім CSV-стрімінгу: доти `stream_csv` був приватним методом
# `Api::V1::ReportsController`, і дротування другого CSV-споживача (ledger
# гаманця) означало б другу копію заголовків. Ліниве тіло (`Enumerator`) —
# щоб великий експорт не збирався в один рядок у памʼяті.
module CsvStreamable
  extend ActiveSupport::Concern

  private

  def stream_csv(filename, &block)
    headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""
    headers["Content-Type"] = "text/csv"
    headers["Cache-Control"] = "no-cache"

    self.response_body = Enumerator.new(&block)
  end
end
