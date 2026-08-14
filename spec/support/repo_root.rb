# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "pathname"

# [DOC-T.75] Корінь репозиторію БЕЗ Rails.
#
# Навіщо окремий якір. Пʼять спек читають дерева, що лежать поза `app`/`lib`/`spec`
# (`.github/**` · `.claude/**` · `terraform/**` · `deploy/**`), і саме тому вони
# переїхали з джоби `test` у `docs_check`: фільтр `ci.yml` (`ruby || ci`) жодного
# з цих дерев не містить, тож гейти не бігли на змінах того, що стережуть
# (§Guard-craft #1 — декоративний за ВХОДОМ). Фільтр `docs.yml` покриває всі
# чотири, але та джоба свідомо БЕЗ Rails-рантайму, тож `Rails.root` там не існує.
#
# ⚠️ Шлях виводиться з розташування САМОГО файлу, ніколи з ENV чи конфігурованого
# дефолту: фікстура, що бере корінь із налаштування, зелена на машині автора й
# мовчки роззброюється там, де це налаштування інше (§Mutation-verify).
REPO_ROOT = Pathname.new(File.expand_path("../..", __dir__)) unless defined?(REPO_ROOT)
