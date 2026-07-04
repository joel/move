# frozen_string_literal: true

# Lookbook (#530) — component browser / preview environment for the Phlex
# Ui::* kit, mounted at /lookbook in development (see config/routes.rb and
# doc/project/component-previews.md). The gem lives in the :development group,
# so everything here is guarded on the constant being defined.
#
# Preview classes live in spec/components/previews/ — deliberately OUTSIDE
# app/**: that keeps them clear of the Steep annotation-coverage spec
# (spec/architecture/type_annotations_spec.rb), Packwerk (spec/** excluded),
# and the Move/* cops. Lookbook adds the preview path to the development
# autoload paths, so Zeitwerk naming applies (ui/button_preview.rb →
# Ui::ButtonPreview).
if defined?(Lookbook)
  Rails.application.configure do
    config.lookbook.project_name = "#{config.x.brand_name} UI"
    config.lookbook.preview_paths << Rails.root.join("spec/components/previews").to_s
    # Where the previewed component sources live — powers the source inspector.
    config.lookbook.component_paths << Rails.root.join("app/components").to_s
    config.lookbook.preview_layout = "lookbook_preview"
    # Per-preview theme dropdown (dark first — dark is the brand default). The
    # lookbook_preview layout applies the selection as the `dark` class.
    config.lookbook.preview_display_options = { theme: %w[dark light] }
  end
end

# Lookbook force-loads view_component (a hard dependency it no longer uses for
# rendering when previews subclass Lookbook::Preview). Keep ViewComponent fully
# inert: without this, its engine would mount its own preview routes in dev.
Rails.application.configure do
  config.view_component.previews.enabled = false if defined?(ViewComponent)
end
