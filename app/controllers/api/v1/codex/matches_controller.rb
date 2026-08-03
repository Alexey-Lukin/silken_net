# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Api
  module V1
    module Codex
      # `Codex::Match` is the resource (a single Battle Arena duel). REST
      # actions:
      #   GET  /codex/matches/new   → Turbo Frame Arena with the next pair
      #   POST /codex/matches       → record vote / skip
      #
      # The "Battle Arena" naming is preserved at the UX layer (Phlex
      # `Codex::Battle::Arena` component) — it's a UI label, not a REST noun.
      #
      # Both actions route through `Codex::MatchPolicy` (auth required).
      # Rack::Attack rule: 60 POSTs / 1 minute / actor — see
      # `config/initializers/rack_attack.rb` (`codex/matches/create`).
      class MatchesController < BaseController
        def new
          authorize ::Codex::Match.new(user_id: current_user.id), :create?

          realm = resolve_realm(params[:realm])
          result = ::Codex::PairSelectorService.call(user: current_user, realm: realm)

          unless result.success?
            return render_dashboard(
              title: I18n.t("codex.battle_arena.page_title", default: "Codex · Battle Arena"),
              component: ::Codex::Battle::Arena.new(
                left: nil, right: nil, pair_seed: nil,
                realm: realm, error: result.error
              ),
              status: :unprocessable_content
            )
          end

          render_dashboard(
            title: I18n.t("codex.battle_arena.page_title", default: "Codex · Battle Arena"),
            component: ::Codex::Battle::Arena.new(
              left: result.left, right: result.right,
              pair_seed: result.pair_seed, realm: result.realm,
              error: nil
            )
          )
        end

        def create
          authorize ::Codex::Match.new(user_id: current_user.id), :create?

          pair_seed   = params[:pair_seed].to_s.strip
          winner_slug = params[:winner_slug].presence
          skip        = ActiveModel::Type::Boolean.new.cast(params[:skip])

          result = ::Codex::VoteRecorderService.call(
            user: current_user,
            pair_seed: pair_seed,
            winner_slug: winner_slug,
            skip: skip
          )

          if result.success?
            respond_to do |format|
              format.json do
                render json: { data: ::Codex::MatchBlueprint.render_as_hash(result.match) },
                       status: :created
              end
              # 🔴 [SEC.25] PRG, а не рендер сторінки. Доти тут стояв повний
              # `render_dashboard(status: :created)`, і він ЛИШАВ БРАУЗЕР НА
              # POST-ONLY АДРЕСІ: Turbo на успіху робить `proposeVisit(
              # fetchResponse.location)`, а `location` = `expandURL(response.url)`,
              # тобто `/codex/matches` — маршрут, зареєстрований лише як
              # `only: [:new, :create]`. Отже після КОЖНОГО голосу Reload (і
              # «Назад»→«Вперед») давав `RoutingError`.
              #
              # ⚠️ І тримався той рендер на випадковості: гард Turbo — рівно
              # `statusCode == 200 && !redirected`, тож 201 його МИНАВ. Заміна
              # 201 на 200 «для акуратності» мовчки вимкнула б оновлення арени,
              # лишивши слід тільки в консолі.
              #
              # Побічно зникає дублювання: підбір наступної пари — робота `#new`,
              # і він її вже робить; тут вона стояла другим викликом того самого
              # сервісу з власною гілкою помилки.
              format.html do
                # `&.` тут БУВ і знятий свідомо: `codex_matches.codex_realm_id`
                # оголошено NOT NULL, тож nil-гілка недосяжна за побудовою —
                # тобто це не захист, а мертва гілка, яку нічим покрити.
                redirect_to new_codex_match_path(realm: result.match.realm.slug),
                            status: :see_other
              end
            end
          else
            replay = result.error == "seed_invalid_or_consumed"
            status = replay ? :forbidden : :unprocessable_content
            # [SEC.25 Ф4] Арена — справжні `<form>` без жодного дебаунсу (компонент
            # сам це документує), тож повторний сабміт того самого `pair_seed`
            # (подвійний клік або «назад» на застарілу рамку) — буденний шлях, і він
            # віддавав сирий JSON. Посадка назад на арену: там людина й стоїть, а
            # редирект дає їй свіжу пару замість спожитої.
            #
            # ✅ Обидві стелі, що тут стояли, знято. (1) Realm більше не губиться:
            # форма несе його прихованим полем, і обидві гілки передають далі —
            # це стало ОБОВʼЯЗКОВИМ, щойно успіх перейшов на PRG, бо інакше цикл
            # «редирект → форма → редирект» скидав би реалм на першій же відмові.
            # (2) Два статуси дістали ДВА тексти: для replay голос уже зараховано
            # (дія відбулась), для 422 — не зараховано; один текст на обидва
            # називав би різні події однаково.
            respond_to do |format|
              format.json { render json: { error: result.error }, status: status }
              format.html do
                redirect_to new_codex_match_path(realm: params[:realm].presence),
                            status: :see_other,
                            error: I18n.t(replay ? "flash.codex.match_replay" : "flash.codex.match_rejected")
              end
            end
          end
        end

        private

        def resolve_realm(slug)
          return ::Codex::Realm.ordered.first if slug.blank?

          ::Codex::Realm.find_by(slug: slug) || ::Codex::Realm.ordered.first
        end
      end
    end
  end
end
