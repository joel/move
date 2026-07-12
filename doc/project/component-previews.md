# Component previews — Lookbook

[Lookbook](https://lookbook.build/) is the development-only component browser for
the Phlex `Components::Ui::*` kit (#530). It renders every component scenario in
isolation — variants, states, dark/light — with the component source alongside,
complementing the hand-rolled `/style_guide` page (which stays the single-page
"everything at once" verification surface).

## Running it

Development only. Open **`https://move.move-easy.docker/lookbook`** — the apex
dev host, **not** an org subdomain: the Apartment elevator keeps the apex on the
`public` schema, while an unknown-tenant subdomain would 404. **There is no
production URL** — the gem lives in the `:development` group and the mount is
behind `Rails.env.development?`, so `https://move-easy.org/lookbook` 404s by
construction (verified live at release). After changing the
Gemfile (first install) the dev container needs `bin/cli app rebuild`; after that,
Lookbook live-reloads the UI when preview/component files change (the `listen` gem).

Each preview page has a **theme** display option (toolbar dropdown) that toggles
the `dark` class on the preview iframe — dark first, matching the brand default.

## Where things live

| Piece | Path |
|---|---|
| Preview classes | `spec/components/previews/ui/*_preview.rb` |
| Preview iframe layout | `app/views/layouts/lookbook_preview.html.erb` |
| Engine mount (dev-only) | `config/routes.rb` (`mount Lookbook::Engine, at: "/lookbook"`) |
| Configuration | `config/environments/development.rb` (the Lookbook block — must live in env config, **not** an initializer: Lookbook registers the preview dir on the autoload paths before `config/initializers/*` load) |
| Gems | `Gemfile` `:development` group (`lookbook`, `listen`) |

## Writing a preview

**CI-enforced (#606):** every renderable `Ui::*` component (a class descending
from `Components::Base`) must have a `spec/components/previews/ui/<name>_preview.rb`
— the `spec/architecture/conventions_spec.rb` fitness test fails the `test` job
naming any component that lacks one. Non-renderable helpers under
`app/components/ui/` (e.g. the `NavDestinations` data module) are exempt by
construction.

One preview class per component, one scenario method per meaningful state (the
UX conventions' "cover every state deliberately" applies to previews too):

```ruby
# spec/components/previews/ui/chip_preview.rb
module Ui
  class ChipPreview < Lookbook::Preview
    def room
      render Components::Ui::Chip.new(label: "Kitchen", kind: :room)
    end
  end
end
```

Conventions and gotchas:

- **Subclass `Lookbook::Preview`** (not ViewComponent's) and `render` the Phlex
  instance directly. Content blocks execute outside a Phlex context, so either
  return a plain string or take the component as a block arg
  (`do |c| c.render ... end` / `c.h3 { ... }`).
- **Zeitwerk naming applies** — Lookbook adds the preview path to the dev
  autoload paths, so `ui/button_preview.rb` must define `Ui::ButtonPreview`.
- **Record-backed components use unsaved `FactoryBot.build` records** (factories
  load in development). Never persist from a preview — previews render on the
  `public` schema, and Move-scoped rows must not land there. If the component
  builds routes from the record (e.g. `LabelPrintStatus`), give the built records
  fixed literal ids so the path helpers resolve.
- Scenario annotations (`@!group`, `@label`, `@param`) are YARD-style comments —
  see the [Lookbook annotation docs](https://lookbook.build/guide/previews/annotations).

## Why previews live in `spec/components/previews/`

Deliberately **outside `app/**`** so the preview layer stays out of the
production autoload/eager-load story and clear of three merge-blocking gates:

- the Steep annotation-coverage spec (`spec/architecture/type_annotations_spec.rb`)
  scans `app/components/**` / `app/views/**` and would demand `#:` annotations on
  every preview method;
- Packwerk includes all of `app/**` (previews reference many packs' constants —
  `spec/**` is excluded);
- the `Move/*` cops exclude `spec/**`.

Plain RuboCop still lints the preview files.

## Integration notes (why no CSP/auth changes were needed)

- **CSP**: Lookbook's controllers call `content_security_policy(false)`, so its
  UI and the preview iframes opt out of the app's enforcing nonce policy —
  nothing to relax on the app side, and app pages keep the strict policy.
- **Auth**: a mounted Rack engine bypasses `ApplicationController` gating and
  Rodauth only claims its own paths, so `/lookbook` is unauthenticated — fine
  because the gem/mount exist only in development.
- **ViewComponent**: a hard transitive dependency of the `lookbook` gem, loaded
  but unused (`using_view_component = false`); its own preview routes are
  disabled in `config/environments/development.rb`.
- **Tailwind**: `app/assets/tailwind/application.css` has an `@source` for the
  preview dir so preview-only utility classes compile (dev CSS is rebuilt by
  `bin/rails tailwindcss:watch` / `tailwindcss:build`).
