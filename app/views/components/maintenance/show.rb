# frozen_string_literal: true

module Maintenance
  class Show < ApplicationComponent
    def initialize(record:, photos:, pagy_photos:)
      @record      = record
      @user        = record.user
      @photos      = photos
      @pagy_photos = pagy_photos
    end

    def view_template
      div(class: "space-y-8 animate-in fade-in duration-700") do
        render_header
        div(class: "grid grid-cols-1 xl:grid-cols-3 gap-8") do
          div(class: "xl:col-span-2 space-y-8") do
            render_evidence_gallery
            render_notes_panel
            render_cost_breakdown
          end
          div(class: "space-y-8") do
            render_metadata_panel
            render_gps_panel
            render_hardware_panel
          end
        end
      end
    end

    private

    # =========================================================================
    # HEADER
    # =========================================================================
    def render_header
      div(class: "flex flex-col md:flex-row justify-between items-start md:items-center " \
                 "p-8 border border-emerald-900 bg-black shadow-2xl relative overflow-hidden") do
        div(class: "absolute top-0 right-0 p-4 text-[80px] font-bold text-emerald-900/5 select-none") do
          @record.action_type.to_s.upcase
        end

        div do
          h2(class: "text-3xl font-extralight tracking-tighter text-emerald-400") do
            "Record // ##{@record.id}"
          end
          div(class: "flex flex-wrap items-center gap-3 mt-2") do
            action_badge(@record.action_type)
            hardware_badge(@record.hardware_verified)
            span(class: "text-[9px] text-gray-600 font-mono") do
              @record.performed_at&.strftime("%d.%m.%Y // %H:%M UTC")
            end
          end
        end

        div(class: "mt-6 md:mt-0 flex items-center space-x-4") do
          a(
            href: helpers.new_api_v1_maintenance_record_path(
              maintainable_type: @record.maintainable_type,
              maintainable_id: @record.maintainable_id
            ),
            class: "px-4 py-2 border border-emerald-800 text-emerald-800 hover:border-emerald-500 " \
                   "hover:text-emerald-500 transition-all uppercase text-[9px] tracking-widest"
          ) { "+ New Record" }

          unless @record.hardware_verified
            button_to(
              "Verify Hardware →",
              helpers.verify_api_v1_maintenance_record_path(@record),
              method: :patch,
              class: "px-4 py-2 border border-amber-700 text-amber-700 hover:bg-amber-700 " \
                     "hover:text-black transition-all uppercase text-[9px] tracking-widest",
              data: { turbo_confirm: "STM32 acknowledged the pulse for record ##{@record.id}?" }
            )
          end
        end
      end
    end

    # =========================================================================
    # EVIDENCE GALLERY
    # =========================================================================
    def render_evidence_gallery
      div(class: "p-8 border border-emerald-900 bg-zinc-950") do
        h3(class: "text-[10px] uppercase tracking-[0.4em] text-emerald-700 mb-6") { "Evidence Protocol" }

        if @pagy_photos.count > 0
          render Maintenance::PhotoGallery.new(
            record: @record, photos: @photos, pagy: @pagy_photos, editable: true
          )
        else
          render_no_photos_placeholder
        end
      end
    end

    def render_no_photos_placeholder
      div(class: "border border-dashed border-emerald-900/40 p-10 text-center") do
        p(class: "text-emerald-900 uppercase tracking-widest text-[10px]") { "No Photos Attached" }
        if %w[repair installation].include?(@record.action_type)
          p(class: "text-red-800 text-[9px] mt-2 font-mono") do
            "⚠ Trust Protocol requires photos for #{@record.action_type}"
          end
        end
        a(
          href: helpers.edit_api_v1_maintenance_record_path(@record),
          class: "inline-block mt-4 px-4 py-2 border border-emerald-900 text-emerald-900 " \
                 "hover:border-emerald-500 hover:text-emerald-500 uppercase text-[9px] tracking-widest transition-all"
        ) { "Attach Evidence →" }
      end
    end

    # =========================================================================
    # NOTES
    # =========================================================================
    def render_notes_panel
      div(class: "p-6 border border-emerald-900 bg-black") do
        h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-4") { "Field Notes" }
        p(class: "text-sm text-gray-300 font-mono leading-relaxed whitespace-pre-wrap") { @record.notes }
      end
    end

    # =========================================================================
    # COST BREAKDOWN (OpEx Series C)
    # =========================================================================
    def render_cost_breakdown
      div(class: "p-6 border border-emerald-900 bg-emerald-950/5") do
        h3(class: "text-[10px] uppercase tracking-widest text-emerald-700 mb-6") { "OpEx Breakdown" }

        div(class: "grid grid-cols-3 gap-6") do
          cost_card(
            "Labor",
            @record.labor_hours ? "#{@record.labor_hours}h × $#{MaintenanceRecord::LABOR_RATE_PER_HOUR}" : "—",
            @record.labor_hours ? "$#{(@record.labor_hours.to_f * MaintenanceRecord::LABOR_RATE_PER_HOUR).round(2)}" : "$0.00"
          )
          cost_card(
            "Parts",
            "Components replaced",
            @record.parts_cost ? "$#{@record.parts_cost}" : "$0.00"
          )
          cost_card("Total Cost", "Labor + Parts", "$#{@record.total_cost.round(2)}", highlight: true)
        end
      end
    end

    def cost_card(label, sub, value, highlight: false)
      div(class: "p-4 border border-emerald-900/40 bg-zinc-950") do
        p(class: "text-[9px] uppercase tracking-widest text-emerald-800") { label }
        p(class: "text-[8px] text-gray-600 mt-1 mb-3") { sub }
        span(class: tokens("text-2xl font-light", highlight ? "text-emerald-400" : "text-gray-300")) { value }
      end
    end

    # =========================================================================
    # METADATA
    # =========================================================================
    def render_metadata_panel
      div(class: "p-6 border border-emerald-900 bg-black space-y-4") do
        h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Intervention Metadata" }

        div(class: "space-y-3 text-[10px] font-mono") do
          meta_row("Technician", "#{@user.first_name} #{@user.last_name}")
          meta_row("Role", @user.role.to_s.upcase)
          meta_row("Target", "#{@record.maintainable_type} // #{@record.maintainable&.did || @record.maintainable&.uid}")
          meta_row("Action", @record.action_type.to_s.upcase)
          meta_row("Photos", @record.photos.size.to_s)
          if @record.ews_alert_id
            meta_row("EWS Alert", "##{@record.ews_alert_id}")
          end
          meta_row("Created", @record.created_at&.strftime("%d.%m.%Y %H:%M"))
          meta_row("Updated", @record.updated_at&.strftime("%d.%m.%Y %H:%M"))
        end

        div(class: "pt-4 border-t border-emerald-900/30") do
          a(
            href: helpers.edit_api_v1_maintenance_record_path(@record),
            class: "block w-full text-center py-2 border border-emerald-900 text-[9px] uppercase " \
                   "text-emerald-700 hover:border-emerald-500 hover:text-emerald-500 transition-all"
          ) { "Edit Record →" }
        end
      end
    end

    # =========================================================================
    # GPS PANEL (Anti-Sofa-Repair)
    # =========================================================================
    def render_gps_panel
      div(class: "p-6 border border-emerald-900 bg-black space-y-4") do
        h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Intervention Coordinates" }

        if @record.latitude.present? && @record.longitude.present?
          div(class: "space-y-3 text-[10px] font-mono") do
            meta_row("Lat", @record.latitude.to_s)
            meta_row("Lng", @record.longitude.to_s)
            render_gps_drift_check
          end

          a(
            href: "https://www.google.com/maps?q=#{@record.latitude},#{@record.longitude}",
            target: "_blank",
            class: "block mt-4 text-center p-2 border border-emerald-800 text-emerald-600 " \
                   "hover:bg-emerald-900 hover:text-white transition-all uppercase text-[9px]"
          ) { "Locate Patrol →" }
        else
          p(class: "text-emerald-900 text-[9px] uppercase tracking-widest") { "No GPS recorded" }
          p(class: "text-gray-600 text-[8px] mt-1") { "Captured via mobile app at time of record creation." }
        end
      end
    end

    def render_gps_drift_check
      # Порівнюємо координати патрульного з координатами Tree
      return unless @record.maintainable_type == "Tree"

      tree = @record.maintainable
      return unless tree&.latitude.present? && tree&.longitude.present?

      drift_m = SilkenNet::GeoUtils.haversine_distance_m(
        @record.latitude.to_f, @record.longitude.to_f,
        tree.latitude.to_f, tree.longitude.to_f
      )

      color = if drift_m < 50 then "text-emerald-400"
      elsif drift_m < 500 then "text-amber-400"
      else "text-red-400"
      end

      div(class: "flex justify-between border-t border-emerald-900/30 pt-2 mt-2") do
        span(class: "text-gray-600") { "Drift from Tree:" }
        span(class: color) { "#{drift_m.round} m" }
      end
    end

    # =========================================================================
    # HARDWARE
    # =========================================================================
    def render_hardware_panel
      div(class: "p-6 border border-emerald-900 bg-black space-y-4") do
        div(class: "flex justify-between items-center") do
          h3(class: "text-[10px] uppercase tracking-widest text-emerald-700") { "Hardware State" }
          if @record.hardware_verified
            span(class: "h-2 w-2 rounded-full bg-emerald-500 shadow-[0_0_8px_#10b981]")
          else
            span(class: "h-2 w-2 rounded-full bg-amber-600")
          end
        end

        div(class: "text-[10px] font-mono space-y-3") do
          meta_row("STM32 Verified", @record.hardware_verified ? "YES" : "PENDING")
          meta_row("Record Type", @record.action_type.to_s.upcase)
        end

        unless @record.hardware_verified
          div(class: "pt-4 border-t border-emerald-900/30") do
            button_to(
              "Verify Now →",
              helpers.verify_api_v1_maintenance_record_path(@record),
              method: :patch,
              class: "w-full py-2 border border-amber-800 text-[9px] uppercase text-amber-700 " \
                     "hover:bg-amber-900 hover:text-white transition-all",
              data: { turbo_confirm: "Mark STM32 pulse confirmed for record ##{@record.id}?" }
            )
          end
        end
      end
    end

    # =========================================================================
    # HELPERS
    # =========================================================================
    def action_badge(type)
      colors = {
        "repair" => "border-amber-600 text-amber-600",
        "installation" => "border-blue-600 text-blue-600",
        "inspection" => "border-emerald-600 text-emerald-600",
        "cleaning" => "border-cyan-700 text-cyan-700",
        "decommissioning" => "border-red-800 text-red-800"
      }
      cls = colors[type] || "border-gray-600 text-gray-600"
      span(class: "text-[9px] px-2 py-0.5 border font-mono uppercase tracking-widest #{cls}") { type }
    end

    def hardware_badge(verified)
      if verified
        span(class: "text-[9px] px-2 py-0.5 border border-emerald-600 text-emerald-600 font-mono uppercase") do
          "✓ HW Verified"
        end
      else
        span(class: "text-[9px] px-2 py-0.5 border border-amber-900 text-amber-900 font-mono uppercase") do
          "Pending Verify"
        end
      end
    end

    def meta_row(label, value)
      div(class: "flex justify-between") do
        span(class: "text-gray-600") { "#{label}:" }
        span(class: "text-emerald-400 truncate ml-2") { value }
      end
    end

    # Haversine distance delegated to shared utility (SilkenNet::GeoUtils)
  end
end
