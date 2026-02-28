module Views
  module Components
    module Navigation
      class Sidebar < ApplicationComponent
        def initialize(user:)
          @user = user
        end

        def view_template
          aside(class: "w-64 border-r border-emerald-900 bg-black flex flex-col") do
            logo_section
            nav_links
            user_section
          end
        end

        private

        def logo_section
          div(class: "p-6 border-b border-emerald-900") do
            span(class: "text-xl font-bold tracking-tighter text-emerald-400") { "SILKEN_NET" }
            p(class: "text-[10px] text-emerald-800") { "D-MRV CORE v2.1" }
          end
        end

        def nav_links
          nav(class: "flex-1 p-4 space-y-2") do
            link_to_nav "Clusters", clusters_path, icon: "map"
            link_to_nav "Alerts", alerts_path, icon: "bell", alert: true
            link_to_nav "Contracts", contracts_path, icon: "shield"
            link_to_nav "Oracle", oracle_visions_path, icon: "eye"
          end
        end

        def link_to_nav(label, path, icon:, alert: false)
          a(href: path, class: "flex items-center space-x-3 p-2 rounded hover:bg-emerald-950 transition-colors group") do
            span(class: tokens("text-sm uppercase tracking-widest", alert ? "text-red-500" : "text-emerald-600 group-hover:text-emerald-400")) { label }
          end
        end

        def user_section
          div(class: "p-4 border-t border-emerald-900") do
            p(class: "text-xs font-mono") { @user.email_address }
            p(class: "text-[10px] uppercase text-gray-600") { @user.role }
          end
        end
      end
    end
  end
end
