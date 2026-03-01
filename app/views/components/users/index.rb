module Views
  module Components
    module Users
      class Index < ApplicationComponent
        def initialize(users:)
          @users = users
        end

        def view_template
          div(class: "space-y-8 animate-in fade-in duration-700") do
            header_section
            
            div(class: "border border-emerald-900 bg-black overflow-hidden") do
              table(class: "w-full text-left font-mono text-[11px]") do
                thead(class: "bg-emerald-950/20 text-emerald-800 uppercase text-[9px] tracking-widest") do
                  tr do
                    th(class: "p-4") { "Identity" }
                    th(class: "p-4") { "Role / Access" }
                    th(class: "p-4") { "Neural Link State" }
                    th(class: "p-4 text-right") { "Audit" }
                  end
                end
                tbody(class: "divide-y divide-emerald-900/30") do
                  @users.each { |user| render_user_row(user) }
                end
              end
            end
          end
        end

        private

        def header_section
          div(class: "flex justify-between items-end mb-6") do
            div do
              h3(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700") { "Organization Crew Registry" }
              p(class: "text-xs text-gray-600 mt-1") { "Authorized personnel for ecosystem intervention." }
            end
          end
        end

        def render_user_row(user)
          tr(class: "hover:bg-emerald-950/10 transition-colors group") do
            td(class: "p-4") do
              div(class: "flex items-center space-x-3") do
                div(class: "h-8 w-8 rounded-full bg-emerald-900/20 border border-emerald-800 flex items-center justify-center text-emerald-500 font-bold") { user.first_name[0] }
                span(class: "text-emerald-100") { "#{user.first_name} #{user.last_name}" }
              end
            end
            td(class: "p-4") do
              span(class: tokens("px-2 py-0.5 rounded-sm text-[9px] font-bold uppercase", role_color(user.role))) { user.role }
            end
            td(class: "p-4 text-gray-600") do
               user.last_seen_at ? "Active #{helpers.time_ago_in_words(user.last_seen_at)} ago" : "Link offline"
            end
            td(class: "p-4 text-right") do
              a(href: "#", class: "text-emerald-700 hover:text-white transition-all") { "VIEW_LOGS" }
            end
          end
        end

        def role_color(role)
          case role
          when 'admin' then "bg-red-900/50 text-red-200 border border-red-800"
          when 'forester' then "bg-emerald-900/50 text-emerald-200 border border-emerald-800"
          when 'investor' then "bg-blue-900/50 text-blue-200 border border-blue-800"
          else "bg-zinc-800 text-zinc-400"
          end
        end
      end
    end
  end
end
