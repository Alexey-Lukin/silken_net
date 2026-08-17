# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"

# 🔴 [S6.21] Заявка про другий фактор мусить триматись на МЕХАНІЗМІ, а не на колонці.
#
# `users.otp_required_for_login` читають три поверхні (`users/profile` індикатор ·
# `account_security#show` · `user_blueprint` — публічний серіалізатор), а шлях входу
# його не перевіряє. Тобто прапорець сам по собі не захищає нічого: увімкнений, він
# лише ДРУКУЄ «MFA Active». Тому напрямок «увімкнути» закритий доти, доки вхід не
# навчиться питати другий фактор.
#
# Цей приклад — ПОХІДНА половина гейта: він не пінить відмову (це робить
# `spec/requests/api/v1/account_security_controller_spec.rb`, і саме той пін є
# поведінковим якорем), а тримає ЗВʼЯЗОК між двома незалежними сторонами —
# «вхід перевіряє» ⊥ «запис дозволений». Щойно verify-on-login приїде, приклад
# почервоніє й скаже ВІДКРИТИ шлях назад: гейт знімається разом із причиною, а не
# лишається жити як вічний карантин (§Guard-craft #59 — підстава carve-outʼа тут
# машинно перевідна, тож її гейтують, а не лишають читачеві).
#
# ⚠️ ЧОГО ЦЕЙ ГЕЙТ НЕ БАЧИТЬ (стеля названа явно, інакше зелений читається як
# «перевірено все»):
#   · Він читає ДЖЕРЕЛО, не поведінку: перевірка другого фактора, дописана в
#     ІНШОМУ файлі (концерн, сервіс, middleware), лишить його зеленим. Напрямок
#     цієї сліпоти безпечний — шлях увімкнення просто лишиться закритим, і той,
#     хто будує TOTP, дістане 501 у власному фіксі того ж дня.
#   · Він знімає рядки-коментарі перед скануванням — інакше проза, що ПОЯСНЮЄ
#     відсутність перевірки (така стоїть у `sessions#create`), червонила б його.
#     Наслідок для ручного виміру: рахуючи цей клас грепом, ділі код і прозу
#     (§Guard-craft #10a) — автоматика цю половину не покриє ніколи.
#   · Він не судить ЧИТАЧІВ прапорця: якщо рядок із `true` зʼявиться в БД повз
#     застосунок (консоль, міграція), три поверхні знову казатимуть «MFA Active».
RSpec.describe "MFA claim honesty [S6.21]" do # rubocop:disable RSpec/DescribeClass
  # Периметр входу: обидва файли, крізь які проходить КОЖЕН вхід у застосунок.
  let(:login_path_files) do
    [
      Rails.root.join("app/controllers/api/v1/sessions_controller.rb"),
      Rails.root.join("app/controllers/api/v1/base_controller.rb")
    ]
  end

  let(:writer_file) { Rails.root.join("app/controllers/api/v1/account_security_controller.rb") }

  # Словник, яким виражається ПЕРЕВІРКА другого фактора на вході.
  let(:second_factor_tokens) do
    %w[otp_required_for_login mfa_enabled? consume_recovery_code! otp_attempt totp]
  end

  def code_without_comments(path)
    path.read.lines.reject { |line| line.lstrip.start_with?("#") }.join
  end

  def login_verifies_second_factor?
    login_path_files.flat_map { |f| second_factor_tokens.select { |t| code_without_comments(f).include?(t) } }.uniq
  end

  # Ліхтар на власний підмет: гейт ключується на ФАЙЛИ й на імена методів у них,
  # тож перейменування котрогось спорожнило б скан МОВЧКИ — і зелень означала б
  # «нічого не перевірено», а не «все гаразд» (§Guard-craft #28).
  it "scans a login perimeter that actually exists" do
    missing = login_path_files.reject(&:exist?)
    expect(missing).to be_empty,
      "перейменовано файл шляху входу — периметр гейта осліп: #{missing.join(', ')}"

    expect(code_without_comments(login_path_files.first)).to include("def create"),
      "у `sessions_controller` більше немає `def create` — перевір, де тепер живе вхід"
    expect(code_without_comments(login_path_files.last)).to include("def authenticate_user!"),
      "у `base_controller` більше немає `def authenticate_user!` — перевір, де тепер живе автентифікація"
    expect(writer_file).to exist
  end

  it "keeps the enable path closed exactly while login does not verify a second factor" do
    verified_by = login_verifies_second_factor?
    writer_code = code_without_comments(writer_file)

    if verified_by.any?
      expect(writer_code).not_to include("render_mfa_not_implemented"),
        "вхід уже перевіряє другий фактор (#{verified_by.join(', ')}) — S6.21 приїхав, " \
        "тож wip-гейт на `toggle_mfa` треба ЗНЯТИ разом із цим приписом"
    else
      expect(writer_code).not_to match(/otp_required_for_login:\s*true/),
        "шлях входу другого фактора не перевіряє, а `account_security` ставить прапорець — " \
        "це заявка на захист, якого немає (три поверхні надрукують «MFA Active»)"
      expect(writer_code).to include("render_mfa_not_implemented"),
        "wip-гейт на напрямку «увімкнути» зник, а verify-on-login не приїхав"
    end
  end
end
