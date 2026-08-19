# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

module Views
  module Shared
    module UI
      class PhotoCard < ApplicationComponent
        # @param photo [ActiveStorage::Blob] must respond to :filename, :byte_size, :representable?
        # @param record [MaintenanceRecord] parent record for delete path
        # @param editable [Boolean] show delete button
        def initialize(photo:, record:, editable: false)
          raise ArgumentError, "photo must respond to :filename" unless photo.respond_to?(:filename)

          @photo    = photo
          @record   = record
          @editable = editable
        end

        def view_template
          div(class: card_classes) do
            render_preview
            render_meta_overlay
            render_delete_button if @editable
          end
        end

        private

        def card_classes
          "relative group border border-gaia-border bg-gaia-surface overflow-hidden " \
            "shadow-sm dark:shadow-none " \
            "hover:border-gaia-primary transition-all duration-200 ease-in-out"
        end

        def render_preview
          a(
            href: rails_blob_path(@photo, disposition: "inline"),
            target: "_blank",
            rel: "noopener noreferrer",
            aria_label: t("ui.photo_card.view_photo", filename: @photo.filename),
            class: preview_link_classes
          ) do
            if @photo.representable?
              img(
                src: rails_representation_path(@photo.variant(:thumb)),
                alt: @photo.filename.to_s,
                loading: "lazy",
                class: "w-full h-full object-cover hover:scale-105 transition-transform duration-300"
              )
            else
              render_file_fallback
            end
          end
        end

        def preview_link_classes
          "block aspect-square overflow-hidden " \
            "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-gaia-primary-strong"
        end

        def render_file_fallback
          div(class: "w-full h-full flex flex-col items-center justify-center gap-1 p-2 bg-gaia-surface-sunken") do
            span(class: "text-gaia-primary text-2xl", aria_hidden: "true") { "📎" }
            span(class: "text-mini text-gaia-primary font-mono truncate text-center") { @photo.filename.to_s }
            span(class: "text-micro text-gaia-text-muted") { number_to_human_size(@photo.byte_size) }
          end
        end

        def render_meta_overlay
          div(class: "absolute bottom-0 inset-x-0 bg-gaia-surface-overlay p-1.5 opacity-0 group-hover:opacity-100 transition-opacity duration-200") do
            p(class: "text-micro font-mono text-gaia-primary truncate") { @photo.filename.to_s }
            p(class: "text-micro text-gaia-text-muted") { number_to_human_size(@photo.byte_size) }
          end
        end

        def render_delete_button
          # 🔴 [UI.3] `group-focus-within` тут не косметика: `button_to` рендерить
          # СПРАВЖНЮ `<button>`, тож клавіатура доходить до неї, поки контейнер
          # лишається `opacity-0` — фокус на невидимому елементі, WCAG 2.4.7.
          # ⚠️ Сусідній `render_meta_overlay` тієї ж потреби НЕ має: у ньому лише
          # `<p>`, нічого фокусованого — периметр класу виміряний, не припущений.
          div(class: "absolute top-1 right-1 opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 transition-opacity duration-200") do
            button_to(
              "×",
              maintenance_record_photo_path(@record, @photo),
              method: :delete,
              aria: { label: t("ui.photo_card.remove_photo", filename: @photo.filename) },
              class: delete_button_classes,
              data: { turbo_confirm: t("ui.photo_card.confirm_remove") }
            )
          end
        end

        def delete_button_classes
          "h-6 w-6 bg-status-danger text-status-danger-text text-sm font-bold " \
            "hover:bg-status-danger-accent hover:text-gaia-text-strong " \
            "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-status-danger-accent " \
            "disabled:opacity-50 disabled:cursor-not-allowed " \
            "transition-colors duration-200 ease-in-out"
        end
      end
    end
  end
end
