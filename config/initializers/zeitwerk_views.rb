# frozen_string_literal: true

# Autoload Views::Shared:: namespace from app/views/shared/.
# Components in app/views/components and app/views/layouts are already
# autoloaded via config.autoload_paths (see config/application.rb).
# Shared UI primitives live under app/views/shared/ and use the
# Views::Shared:: prefix (e.g. Views::Shared::UI::StatusBadge).
module ::Views; end
module ::Views::Shared; end

Rails.autoloaders.main.inflector.inflect("ui" => "UI")

Rails.autoloaders.main.push_dir(
  Rails.root.join("app/views/shared"),
  namespace: Views::Shared
)
