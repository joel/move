---
name: ui-designer
description: Build production-grade frontend interfaces using Tailwind CSS, Phlex components, and Hotwire (Turbo + Stimulus). Use this skill whenever the user asks to build, style, or improve web pages, UI components, layouts, forms, navigation, dashboards, or any visual frontend element. Also use when the user mentions designing a view, creating a Phlex component, styling with Tailwind, adding a sidebar, building a table, creating a card, or beautifying any web UI. This skill has access to a 657-component reference library to produce polished, consistent results. Always trigger this skill for ANY UI-related work -- even small styling tweaks, layout adjustments, or "make this look better" requests.
compatibility: Rails project with Phlex (Components::Base) + Tailwind CSS standalone (no Node/npm) + Hotwire (Turbo + Stimulus). Requires a local clone of the Tailwind UI component library at ~/Workspace/WebUIComponents/TailwindCSS/. A project-local component registry (e.g. a ui_library/ directory) is optional and used only if present.
---

# UI Designer

Build and modify frontend interfaces for this Rails + Phlex + Tailwind project. Every UI change should go through this skill to ensure consistency with the design system and reuse of existing library components.

## Component Reference Library

This skill draws from a local library of 657 Tailwind CSS component templates (path documented in the `compatibility` frontmatter). Before building any non-trivial UI element, read `references/component_library.md` — it has the full category index (364 Application UI + 114 E-commerce + 179 Marketing), the decision flow for picking a template, the Phlex translation example, and how to browse the library.

If the library path is missing on this machine, stop and ask the user rather than inventing class names.

## Project Design System

The source of truth for tokens, component classes, and their exact values is `app/assets/tailwind/application.css`. Read it before building; the tables below describe the house style and intent, but the CSS file defines the actual values.

### CSS Tokens (`app/assets/tailwind/application.css`)

| Token | Purpose |
|-------|---------|
| `--ha-bg` | Page background |
| `--ha-surface` | Card/section surfaces |
| `--ha-card` | Card background |
| `--ha-card-border` | Card border color |
| `--ha-border` | General border color |
| `--ha-text` | Primary text |
| `--ha-muted` | Secondary/meta text |
| `--ha-accent` | Primary accent |
| `--ha-danger` | Destructive actions |
| `--ha-surface-hover` | Hover background |

### Component CSS Classes

| Class | What it provides |
|-------|-----------------|
| `ha-card` | Rounded card surface — border, background, shadow, hover lift |
| `ha-card-actions` | Top border + padding for card action buttons |
| `ha-button` | Pill button with padding and transitions |
| `ha-button-primary` | Accent-colored button |
| `ha-button-secondary` | Muted border button |
| `ha-button-danger` | Destructive button |
| `ha-input` | Rounded input — border, background, focus ring |
| `ha-overline` | Small, semibold, uppercase, tracking-wide, muted label |
| `ha-nav-item` | Sidebar navigation item |
| `ha-rise` | Entrance animation (slide up + fade in) |
| `ha-fade-in` | Fade-in entrance animation |

Refer to `app/assets/tailwind/application.css` for the exact radii, colors, shadows, and timings these classes apply.

### Tailwind JIT Constraint

The Docker container compiles Tailwind in JIT mode -- **only classes already used in the codebase exist in the stylesheet.** If you use a class for the first time (e.g., `p-5`, `leading-relaxed`), it will have **zero effect** until `bin/cli app rebuild` recompiles the CSS.

**Verify each class is already compiled before you use it.** Do not trust a
static "safe list" — the compiled set changes every time a component is
added or removed. Probe the candidate classes you intend to use against the
actual source (`app/components` + `app/views`):

```bash
# Returns USED(n) if the class already appears in a view/component
# (hence compiled), or —ABSENT— if using it requires a rebuild.
probe() { c="$1"; n=$(grep -rEl "(^|[\" ])$c([\" ]|$)" app/components app/views 2>/dev/null | wc -l); printf "%-20s %s\n" "$c" "$([ "$n" -gt 0 ] && echo "USED($n)" || echo "—ABSENT—")"; }
for c in p-5 w-2 h-3 ring-2 border-l "top-1/2" leading-relaxed; do probe "$c"; done
```

Treat `—ABSENT—` classes as unavailable: either pick a compiled
equivalent, or, if a genuinely new class is unavoidable, use it and note
**"Requires `bin/cli app rebuild`"** in your report so the rebuild +
visual re-verification happens before the change is considered done.

### Component Conventions

These are the project's house style. They are conventions, not hard rules — match what the surrounding components already do.

| Convention | Value |
|-----------|-------|
| Page sections | `space-y-8` |
| Card padding | `p-6` (list cards), `p-4` (compact inline) |
| Card grid | `gap-4` |
| Section heading -> content | `space-y-6` |
| Card content groups | `space-y-4` |
| Card ID | `id: dom_id(@record)` via `Phlex::Rails::Helpers::DOMID` |
| Card overline | `p(class: "ha-overline") { "Label" }` |
| Card actions | `div(class: "ha-card-actions") { buttons }` |
| Entrance animation | `ha-rise` with staggered `animation-delay` |
| Dark mode | Class-based (`.dark`), all tokens have dual values |

### Phlex View Structure

```ruby
module Views
  module ResourceName
    class ActionName < Views::Base
      include Phlex::Rails::Helpers::LinkTo
      # ... other helpers as needed

      def initialize(resource:)
        @resource = resource
      end

      def view_template
        div(class: "space-y-8") do
          render Components::PageHeader.new(
            section: "Section", title: "Title"
          ) { render_header_actions }
          render_content
        end
      end
    end
  end
end
```

## Workflow

1. **Receive UI task** (new page, new component, styling change)
2. **Search the library** for matching components
3. **Read existing project components** to match conventions
4. **Build the Phlex component** adapting library HTML to project patterns
5. **Verify with agent-browser** that it renders correctly
6. **Check for Bullet N+1 alerts** on the page (see the product-review skill)
7. **(Optional) Update the component registry** if the project maintains one — see appendix below

## Existing Project Components

Run `ls app/components/*.rb` to see the current set — match the naming and structural conventions of the existing files when adding new ones. (Intentionally not listed inline: the component set changes frequently and a static list goes stale the moment a component is added or renamed.)

## Appendix: Optional Component Registry

If the project maintains a component registry (e.g. a `ui_library/` directory that tracks which library components are in use and how they map to project Phlex components), add or update an entry when you create a component. If no such directory exists, skip this section entirely — it is not required and the skill does not depend on it.

**Each entry is typically a YAML file** named after the project component:

```yaml
# ui_library/post_card.yml
component: Components::PostCard
file: app/components/post_card.rb
library_source: application_ui/layout/cards
library_variant: null  # custom, not a direct adaptation
description: Post card with overline, title, metadata, description, state badge, and action buttons.
design_tokens:
  - ha-card (border-radius, border, background, shadow)
  - ha-card-actions (margin-top, border-top, padding-top)
  - ha-overline (font-size, weight, uppercase, tracking, color)
tailwind_classes:
  - p-6, mt-2, text-lg, text-xs, text-sm
  - font-semibold, line-clamp-2
  - flex, items-start, justify-between, gap-4
```

**When adding a new component to a registry:**

1. Check the library for a matching pattern
2. Create a `<registry>/<component_name>.yml` entry
3. Set `library_source` to the library path if adapted, or `null` if custom
4. List the design tokens and Tailwind classes used
5. Validate every entry parses:
   `ruby -ryaml -e 'Dir["<registry>/*.yml"].each { |f| YAML.load_file(f) }'`
   (a quoted token followed by trailing text, or a list item starting with
   `--`, is invalid YAML — quote the whole item instead:
   `- "--ha-token: what it does"`)
6. If the registry has a generated browsable index, regenerate it
   (e.g. `ruby <registry>/generate_index.rb`) and commit the regenerated
   index file alongside the YAML, since the index is a generated artifact.
