module Views
  module Components
    module Firmwares
      class OtaProgressBar < ApplicationComponent
        def initialize(uid:, percent:, current:, total:, status:)
          @uid = uid
          @percent = percent
          @current = current
          @total = total
          @status = status
        end

        def view_template
          div(id: "ota_progress_#{@uid}", class: "p-4 border border-emerald-900 bg-black font-mono") do
            div(class: "flex justify-between items-center mb-2") do
              span(class: "text-[9px] text-emerald-700 uppercase tracking-widest") { "OTA_LINK: #{@uid}" }
              span(class: tokens("text-[9px]", status_color)) { @status }
            end
            
            div(class: "w-full h-1 bg-emerald-950 rounded-full overflow-hidden") do
              div(class: "h-full bg-emerald-500 shadow-[0_0_10px_#10b981] transition-all duration-500", style: "width: #{@percent}%")
            end
            
            div(class: "flex justify-between mt-2 text-[8px] text-gray-600") do
              span { "CHUNK: #{@current} / #{@total}" }
              span { "#{@percent}% COMPLETE" }
            end
          end
        end

        private

        def status_color
          case @status
          when "COMPLETE" then "text-emerald-400"
          when "FAILED"   then "text-red-500 animate-pulse"
          else "text-emerald-600 animate-pulse"
          end
        end
      end
    end
  end
end
