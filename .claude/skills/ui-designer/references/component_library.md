# Tailwind Component Reference Library

The project draws from a 657-component Tailwind CSS reference library. The path is documented in the skill's `compatibility` frontmatter — if that path is missing on this machine, stop and ask the user rather than inventing class names.

## Library Structure

| Category | Count | Path |
|----------|-------|------|
| **Application UI** | 364 | `application_ui/` |
| -- Application Shells | 23 | `application_shells/` (sidebar, stacked, multi-column) |
| -- Data Display | 19 | `data_display/` (calendars, description lists, stats) |
| -- Elements | 45 | `elements/` (avatars, badges, buttons, button groups, dropdowns) |
| -- Feedback | 12 | `feedback/` (alerts, empty states) |
| -- Forms | 74 | `forms/` (action panels, checkboxes, comboboxes, form layouts, input groups, radio groups, select menus, sign-in forms, textareas, toggles) |
| -- Headings | 25 | `headings/` (card headings, page headings, section headings) |
| -- Layout | 38 | `layout/` (cards, containers, dividers, list containers, media objects) |
| -- Lists | 44 | `lists/` (feeds, grid lists, stacked lists, tables) |
| -- Navigation | 54 | `navigation/` (breadcrumbs, command palettes, navbars, pagination, progress bars, sidebar navigation, tabs, vertical navigation) |
| -- Overlays | 24 | `overlays/` (drawers, modal dialogs, notifications) |
| -- Page Examples | 6 | `page_examples/` (detail, home, settings screens) |
| **Ecommerce** | 114 | `ecommerce/` |
| **Marketing** | 179 | `marketing/` |

## How to Use the Library

**Before creating any new UI component, search the library first.** The path prefix is from the `compatibility` field:

```bash
# Search by component type
ls ~/Workspace/WebUIComponents/TailwindCSS/application_ui/elements/badges/
ls ~/Workspace/WebUIComponents/TailwindCSS/application_ui/layout/cards/
ls ~/Workspace/WebUIComponents/TailwindCSS/application_ui/lists/stacked_lists/

# Read a component to see the HTML/Tailwind pattern
cat ~/Workspace/WebUIComponents/TailwindCSS/application_ui/elements/badges/flat.html
```

### Decision flow

1. **Search the library** for the component type you need (card, badge, form, list, etc.)
2. **Found a match?** Read the HTML, adapt it to Phlex syntax, apply project design tokens (`--ha-*` CSS variables). If the project maintains a component registry, document the mapping there (see the optional appendix in the main SKILL.md).
3. **No match?** Build from scratch using the project design system. If a registry exists, add an entry for future reference.

## Adapting Library Components to Phlex

Library components are raw HTML + Tailwind. To use them in this project:

1. Read the HTML from the library file
2. Convert to Phlex Ruby syntax (HTML tags become method calls)
3. Replace hardcoded Tailwind colors with project CSS variables (`--ha-text`, `--ha-muted`, `--ha-accent`, etc.)
4. Apply project conventions (see the Project Design System section in SKILL.md)
5. If the project maintains a component registry, document the adaptation there

### Example: Library badge → Project badge

Library HTML (`application_ui/elements/badges/flat.html`):

```html
<span class="inline-flex items-center rounded-full bg-green-100 px-2 py-1 text-xs font-medium text-green-700">Badge</span>
```

Phlex adaptation:

```ruby
span(class: "rounded-full px-3 py-1 text-xs font-medium " \
            "bg-emerald-100 text-emerald-800 " \
            "dark:bg-emerald-500/10 dark:text-emerald-300") do
  plain "Badge"
end
```

Changes from the library version: added dark mode variants, used project-consistent spacing (`px-3 py-1`), matched the project's border-radius language.

## Browsing the Library

The reference library has a browsable `index.html`:

- **Reference library:** `open ~/Workspace/WebUIComponents/TailwindCSS/index.html` (657 components)

If the project maintains its own component registry with a generated index (e.g. `ui_library/index.html`), open that to browse the project's components; regenerate it after adding or modifying entries (see the optional appendix in the main SKILL.md).
