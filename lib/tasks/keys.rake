# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

# [FW.17 · SEC.40] DR ключів дерев і вікон анти-повтору після відкату БД із бекапу — runbook docs/06_06 §5.8.
# Потрібен PROVISIONING_MASTER_KEY (ключі деривуються в процесі й процесу не
# покидають: друкуються лише епоха й версія).
namespace :keys do
  desc "[FW.17 DR] Пробне розшифрування захопленого CCM-кадру епохами e…e+AHEAD і версіями 0…MAX_VERSION. FRAME=<hex 30 Б ефіру або 31 Б запису з логу MIC-фейлу> [AHEAD=4] [MAX_VERSION=16] [APPLY=1 — відремонтувати рядок]"
  task probe_epoch: :environment do
    abort "Usage: rake keys:probe_epoch FRAME=<hex> [AHEAD=4] [MAX_VERSION=16] [APPLY=1]" if ENV["FRAME"].blank?

    finding = Security::KeyEpochProbe.probe(ENV["FRAME"], ahead: Integer(ENV.fetch("AHEAD", "4")),
                                                          max_version: Integer(ENV.fetch("MAX_VERSION", "16")))
    abort "Жодна пара (епоха, версія) кадру не відкрила — розширити AHEAD/MAX_VERSION або кадр не цього вузла." unless finding

    puts "Кадр відкривається: epoch=#{finding.epoch} key_version=#{finding.key_version}"
    next unless ENV["APPLY"] == "1"

    Security::KeyEpochProbe.repair!(finding)
    puts "Рядок #{finding.device_uid} відремонтовано (grace закрито, аудит записано)."
  end

  desc "[FW.17 DR] Підняти DLFC адресних команд на MARGIN (1…65535, типово 1024) — усі дерева або DID=SNET-XXXXXXXX. MARGIN > числа команд, виданих після точки бекапу"
  task bump_dlfc: :environment do
    count = Security::KeyEpochProbe.bump_downlink_frame_counters!(margin: Integer(ENV.fetch("MARGIN", "1024")),
                                                                  device_uid: ENV["DID"].presence)
    puts "DLFC піднято в #{count} рядках."
  end

  desc "[SEC.40 DR] Підняти підлогу вікон анти-повтору CCM на FRAMES над відновленим top_fc (і дати вікно деревам без нього). FRAMES > числа кадрів, які дерево могло передати після точки бекапу"
  task fence_ccm_window: :environment do
    abort "Usage: rake keys:fence_ccm_window FRAMES=<n>" if ENV["FRAMES"].blank?

    raised, created = CcmReplayWindow.fence!(frames: Integer(ENV["FRAMES"]))
    puts "Підлогу піднято у #{raised} вікнах; створено #{created} (дерева поточної епохи без вікна)."
  end
end
