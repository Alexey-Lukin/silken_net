# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/browser_contour_inventory")
require Rails.root.join("spec/support/browser_contour_registry")

# [SEC.25] Сторож інваріанта `04_03 §2.2б`: дія браузерного контуру не сміє
# відповідати сирим JSON без `respond_to`.
#
# 🔴 Чому він узагалі потрібен, хоч вісь «закрита». Сім таких гілок закрито
# вручну, і жодна з них не могла почервоніти — периметр міряли грепом, тричі,
# і тричі помилялись. Наступний голий `render json:` у новому екшені проходить
# зеленим так само, як проходили ці. Тобто без цього файла «закрито» означає
# лише «здорове сьогодні».
#
# 🧱 ФОРМА — курована мапа, що ЛИШЕ СКОРОЧУЄТЬСЯ, і це вибір проти двох гірших:
#   · skip-list, який дозволяє дописувати винятки, гниє тихо й за півроку стає
#     фактичною політикою (та сама підстава, за якою відхилено `verify_authorized`);
#   · «полагодити всі 70» — відкидається тим, що більшість із них законна, а
#     решта недосяжна з UI, тобто фікс купував би вакуумні піни й з'їдений
#     coverage-слек проти невидимого промаху.
# Реєстр нижче не є дозволом. Кожен запис несе ПІДСТАВУ і УМОВУ ПОВЕРНЕННЯ —
# тобто подію, після якої рядок звідси зникає, а гілка стає must-fix.
#
# ⚠️ Ключ реєстру — `файл#екшен`, свідомо БЕЗ номера рядка: рядки їдуть від
# кожної правки, і реєстр, ключований ними, червонів би на переміщенні коду,
# тобто навчав би себе ігнорувати.
#
# 🔒 Три стелі, названі чесно:
#   1. Гейт бачить СИНТАКСИС, не намір. Він не знає, чи маршрут браузерний —
#      це вирішує `routes.rb` і питання «хто відвантажує клієнта» (ARCH.77).
#      Тому реєстр — декларація людини, а не висновок екстрактора.
#   2. Приватний JSON-хелпер (`render_forbidden_json`) синтаксично не
#      відрізняється від порушення; він у реєстрі саме як хелпер.
#   3. Гейт не ловить зворотний бік — дію, що має `respond_to`, але з ХИБНИМ
#      статусом. Її дім — `04_03 §2.2а` і піни на `media_type`.
RSpec.describe "Браузерний контур: голий render json", type: :model do
  let(:sites)   { BrowserContourInventory.scan }
  let(:actual)  { sites.map { |s| BrowserContourInventory.key_for(s) }.uniq }

  it "жодна НОВА дія не відповідає сирим JSON поза реєстром" do
    unknown = actual - BrowserContourRegistry::ALL.keys

    expect(unknown).to be_empty, <<~MSG
      Нові сайти голого `render json:`/`head` поза `respond_to`:
        #{unknown.join("\n  ")}

      Це або дефект (`04_03 §2.2б` — людина побачить сирий блоб замість сторінки),
      або законний машинний/приватний випадок. Якщо друге — додай рядок у реєстр
      РАЗОМ із підставою та умовою повернення. Голий запис без них не приймається:
      саме так skip-list стає фактичною політикою.
    MSG
  end

  # Друга половина «лише скорочується»: реєстр не сміє переживати свій предмет.
  it "реєстр не гниє — кожен його запис досі існує в дереві" do
    stale = BrowserContourRegistry::ALL.keys - actual

    expect(stale).to be_empty, <<~MSG
      Записи реєстру без відповідного сайту (гілку полагоджено або знято):
        #{stale.join("\n  ")}
      Прибери рядок — інакше реєстр описує світ, якого вже немає.
    MSG
  end

  # Ліхтар: реєстр без підстави — це просто дозвіл.
  it "кожен запис несе змістовну підставу" do
    empty = BrowserContourRegistry::ALL.select { |_k, reason| reason.to_s.strip.length < 20 }
    expect(empty).to be_empty, "порожні підстави: #{empty.keys.join(', ')}"
  end

  # ─── ДРУГА ВІСЬ ТОГО САМОГО ПИТАННЯ [SEC.30] ────────────────────────────────
  # «Хто відвантажує клієнта» вирішує не лише формат відповіді, а й те, чи має
  # запит ambient authority. Машинний вхід її не має (доказ явний у кожному
  # запиті), браузерний має (cookie) — і CSRF стереже саме її.
  #
  # 🔴 Інваріант двобічний НЕ для симетрії: одна половина ловить мертвий
  # машинний вхід (знято автентифікацію, забуто CSRF → 500 до крипто-гарда),
  # друга — відкритий браузерний (знято CSRF там, де cookie реальна). Друга
  # важливіша, бо її промах тихий: жоден тест не падає від зайвої дірки.
  describe "CSRF на машинному контурі [SEC.30]" do
    def forgery_guard?(klass)
      klass._process_action_callbacks.map(&:filter).include?(:verify_authenticity_token)
    end

    it "машинні входи звільнені від CSRF (інакше падають ДО власного гарда)" do
      still_guarded = BrowserContourRegistry::MACHINE_ENTRIES.select { |name, scope| scope == :all && forgery_guard?(name.constantize) }

      expect(still_guarded).to be_empty, <<~MSG
        `skip_before_action :authenticate_user!` без `skip_forgery_protection`: #{still_guarded.keys.join(', ')}.
        Такий вхід падає `InvalidAuthenticityToken` → 500 ще ДО HMAC/Ed25519-перевірки,
        і сюїта цього НЕ бачить, бо test.rb вимикає allow_forgery_protection.
      MSG
    end

    it "частково звільнений контролер ЗБЕРІГАЄ гард поза машинною дією" do
      partial = BrowserContourRegistry::MACHINE_ENTRIES.select { |_n, scope| scope == :partial }.keys
      unguarded = partial.reject { |name| forgery_guard?(name.constantize) }

      expect(unguarded).to be_empty, <<~MSG
        #{unguarded.join(', ')} зняв CSRF на ВЕСЬ контролер.
        Там є дія, що автентифікується cookie-сесією (ambient authority реальна),
        тож зняття мусить бути `only:` — інакше машинний вхід полагоджено ціною
        відкриття браузерного.
      MSG
    end

    # 🔴 Корені ДВА, і це не педантизм: `Api::V1::BaseController` успадковує
    # `ActionController::Base` НАПРЯМУ, спільного предка з `ApplicationController`
    # немає. Перша редакція цього приклада брала лише `ApplicationController
    # .descendants` — тобто перевіряла порожню множину й була зелена назавжди
    # (мутація «зняти CSRF на trees_controller» її не червонила). Той самий клас,
    # що порожня `spec/features/` при живій CI-джобі.
    def all_controllers
      Rails.application.eager_load!
      [ ApplicationController, Api::V1::BaseController ]
        .flat_map { |root| [ root ] + root.descendants }
        .uniq
    end

    it "ніхто ІНШИЙ не знімає CSRF (тиха дірка не має симптому)" do
      # Ліхтар на сам вимір: якщо перелік раптом порожній, приклад доводить ніщо.
      expect(all_controllers.size).to be > 20, "перелік контролерів підозріло малий — вимір зламано"

      unexpected = all_controllers.reject { |k| forgery_guard?(k) }
                                  .map(&:name).compact - BrowserContourRegistry::MACHINE_ENTRIES.keys

      expect(unexpected).to be_empty, <<~MSG
        CSRF знято поза машинним реєстром: #{unexpected.join(', ')}.
        Якщо вхід справді машинний — додай його у BrowserContourRegistry::MACHINE_ENTRIES з підставою.
        Якщо ні — це відкритий браузерний ендпоінт, і промах тут тихий.
      MSG
    end
  end
end
