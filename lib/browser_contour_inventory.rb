# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "prism"

# [SEC.25] Інвентар браузерного контуру: де дія відповідає СИРИМ JSON, не маючи
# `respond_to`.
#
# 🔴 Чому екстрактор, а не греп. Периметр цієї осі тричі міряли грепом і тричі
# помилились: `render(json:` без пробілу греп за виразом не бачить узагалі, а
# `render json:` ВСЕРЕДИНІ `format.json`-блоку — цілком законний і становить
# переважну більшість із ~170 викликів. Тобто відрізняє порушення від норми не
# сам виклик, а його ПОЛОЖЕННЯ в дереві; це властивість AST, і грепом вона
# невиразна в принципі.
#
# ⚠️ Що екстрактор НЕ вирішує (і не має): чи маршрут дії браузерний. Це знає
# лише `config/routes.rb`, і відповідь там залежить від того, ХТО відвантажує
# клієнта (ARCH.77) — питання наміру, не синтаксису. Тому класифікацію робить
# реєстр у спеці, а тут лише факти.
module BrowserContourInventory
  Site = Struct.new(:file, :line, :action, :kind, keyword_init: true)

  RENDER_KINDS = %i[render head].freeze

  class Visitor < Prism::Visitor
    attr_reader :sites

    def initialize(relative_path)
      @path = relative_path
      @sites = []
      @action = nil
      @respond_to_depth = 0
      super()
    end

    def visit_def_node(node)
      previous = @action
      @action = node.name.to_s
      super
      @action = previous
    end

    def visit_call_node(node)
      # `respond_to do |format| … end` — усе всередині блоку законне за побудовою.
      if node.name == :respond_to && node.block
        @respond_to_depth += 1
        super
        @respond_to_depth -= 1
        return
      end

      record(node) if RENDER_KINDS.include?(node.name) && @respond_to_depth.zero?
      super
    end

    private

    def record(node)
      args = node.arguments&.arguments
      return if args.nil? || args.empty?

      kind =
        if node.name == :head
          :head
        elsif json_keyword?(args)
          :render_json
        end
      return if kind.nil?

      @sites << Site.new(file: @path, line: node.location.start_line, action: @action, kind: kind)
    end

    # `render json: …` — і форма без пробілу (`render(json:`) сюди теж потрапляє,
    # бо ми дивимось на вузол, а не на текст.
    def json_keyword?(args)
      args.any? do |arg|
        next false unless arg.is_a?(Prism::KeywordHashNode)

        arg.elements.any? do |el|
          el.is_a?(Prism::AssocNode) && el.key.is_a?(Prism::SymbolNode) && el.key.unescaped == "json"
        end
      end
    end
  end

  module_function

  # @return [Array<Site>] усі виклики `render json:` / `head` ПОЗА `respond_to`
  def scan(root: Rails.root.join("app/controllers"))
    Dir.glob("#{root}/**/*.rb").sort.filter_map do |path|
      result = Prism.parse_file(path)
      next unless result.success?

      relative = Pathname(path).relative_path_from(Rails.root).to_s
      visitor = Visitor.new(relative)
      result.value.accept(visitor)
      visitor.sites
    end.flatten
  end

  # Ключ реєстру — `файл#екшен`, НЕ номер рядка: рядки їдуть від кожної правки,
  # і реєстр, ключований ними, гнив би тихо (саме той режим, за який відхилено
  # skip-list як форму).
  def key_for(site) = "#{site.file}##{site.action}"
end
