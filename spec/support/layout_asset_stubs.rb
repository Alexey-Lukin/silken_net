# frozen_string_literal: true

# Stub asset-resolving helpers on DashboardLayout and AuthLayout in test.
#
# Phlex::Rails::Layout calls `stylesheet_link_tag` / `javascript_importmap_tags`
# which require compiled assets (Propshaft + Tailwind). In test these are
# absent — stubbing avoids Propshaft::MissingAssetError for every request
# spec that renders a full-page layout.
[ DashboardLayout, AuthLayout ].each do |klass|
  next if klass.instance_variable_get(:@test_asset_patched)

  klass.prepend(Module.new do
    def stylesheet_link_tag(*_args, **_opts) = ""
    def javascript_importmap_tags(*_args, **_opts) = ""
  end)
  klass.instance_variable_set(:@test_asset_patched, true)
end
