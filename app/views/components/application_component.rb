# frozen_string_literal: true

class ApplicationComponent < Phlex::HTML
  include Phlex::Rails::Helpers::Routes
  include Phlex::Rails::Helpers::TurboStreamFrom
  include Phlex::Rails::Helpers::TurboFrameTag
  include Phlex::Rails::Helpers::AssetPath

  def tokens(*args, **conditions)
    result = args.compact.join(" ")
    conditional = conditions.filter_map { |cls, flag| cls.to_s if flag }.join(" ")
    combined = [ result, conditional ].reject(&:empty?).join(" ")
    self.class.merger.merge(combined)
  end

  def self.merger
    @merger ||= TailwindMerge::Merger.new
  end
end
