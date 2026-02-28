# frozen_string_literal: true

class ApplicationComponent < Phlex::HTML
  include Phlex::Rails::Helpers::Routes
  include Phlex::Rails::Helpers::TurboStreamFrom
  # Додайте інші необхідні хелпери, наприклад, для Asset Pipeline
  include Phlex::Rails::Helpers::AssetPath

  # Метод для зручного комбінування Tailwind-класів
  def tokens(*args)
    args.compact.join(" ")
  end
end
