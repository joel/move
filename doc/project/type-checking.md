# Static type checking — RBS + Steep

Move type-checks the **actions layer** (`app/actions/**`) with
[Steep](https://github.com/soutaro/steep) 2.0 reading **inline RBS
annotations** (`#:` / `@rbs` comments) natively from the Ruby files — the
[RBS 4 inline syntax](https://github.com/ruby/rbs/blob/master/docs/inline.md),
enabled per target via the Steepfile's `inline: true`. There is **no
rbs-inline preprocessor and no generated `.rbs` tree**: types live next to the
code they describe, so there is nothing to drift. The check is merge-blocking
(CI `lint` job) and runs locally as an Overcommit pre-commit hook — the same
"standards as automated checks" ladder as the `Move/*` cops and Packwerk.

```mermaid
flowchart LR
    A["app/actions/**/*.rb\n#: / @rbs inline annotations"] --> C["steep check\n--no-daemon --severity-level=error"]
    B["sig/*.rbs\nhand shims (dry-monads, …)"] --> C
    S["Steepfile\ntarget :actions, inline: true"] --> C
    C -->|"errors"| F["CI lint job fails / commit blocked"]
    C -->|"warnings & hints\n(unknown app/Rails constants)"| G["non-blocking"]
```

## Why the actions layer first

Business logic lives in `app/actions` (AGENTS.md §1 rule 2): plain Ruby, one
`call` per class, already unit-tested in isolation — the highest-value,
lowest-friction layer to type. Growth is staged like the Packwerk migration:
pack-by-pack (`packs/<domain>/app/actions` next), each addition a `check` line
in the Steepfile. Models, controllers, and Phlex views are deliberately out of
scope for now (see *Known gaps*).

## Running it

```bash
mise x -- bundle exec steep check --no-daemon --severity-level=error
```

~2s at the current scope; no DB, no Rails boot. It runs automatically:

- **CI** — a step in the `lint` job (merge-blocking via branch protection).
- **Pre-commit** — the `Steep` Overcommit hook (`.git-hooks/pre_commit/steep.rb`)
  whenever files under `app/actions/`, `sig/`, or the `Steepfile` are staged.
  Always whole-target: signatures are cross-file, so a staged shim edit can
  break an unstaged action and vice versa.

Two non-obvious flags, both mandatory:

- **`--no-daemon`** — Steep 2.0 defaults to a `steep server` daemon that can
  deadlock in headless environments (observed locally: master thread crash →
  workers wait forever at 0% CPU). The direct check is fast enough not to care.
- **`--severity-level=error`** — the default gate is `warning`, which would
  block on every unknown constant. Domain models have **no RBS signatures
  yet**, so `Move`/`Box`/`Rails` references inside actions surface as
  `UnknownConstant` *warnings* and degrade to `untyped` — non-blocking by
  design. Genuine contract violations (wrong arity, a body that can't produce
  its declared return type, a method call on a *known* type that doesn't
  exist) are errors and block.

## The annotation convention

Full method-type comment on its own line directly above the `def`:

```ruby
    #: (params: untyped, creator: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(params:, creator:)
      move = yield with_responsible(creator) { persist(params, creator) }
      yield emit_event(move)
      Success(move)
    end

    #: (untyped move) -> Dry::Monads::Success[nil]
    def emit_event(move)
      Rails.event.notify("move.created", move_id: move.id)
      Success()
    end
```

House rules (`spec/architecture` of the type system, so to speak):

1. **Domain objects are `untyped`.** A type name that doesn't resolve in the
   RBS environment aborts Steep at signature-load time regardless of severity
   config — and models have no signatures. Real types only for unambiguous
   scalars (`String`, `Symbol`, `Integer`, `bool`, `String?`,
   `Hash[Symbol, untyped]`, …).
2. **`call` returns `Dry::Monads::Result[untyped, untyped]`**; step methods
   returning only `Success(x)` use `Dry::Monads::Success[untyped]`
   (`[nil]` for a bare `Success()`).
3. **A bare do-notation `yield` needs no block declaration** in the method
   type — Steep 2.0 accepts it (verified; earlier designs assumed an optional
   block was required).
4. **The annotation must be its own comment block.** A `#:`/`@rbs` line that
   shares a contiguous comment block with prose can fail to parse
   ("unexpected token for inline leading annotation") — put a blank line
   between a prose comment and the annotation.
5. **`def self.` is not supported by inline RBS yet.** Put `# @rbs skip`
   (bare — no `-- comment` suffix) above the def and declare the singleton
   method in a `sig/*.rbs` file (see `sig/default_vocabularies.rbs`).
6. **`Data.define` / `Struct.new` constants stay unannotated** (dynamic class
   definitions; inline RBS ignores them and inference copes).
7. Local escape hatch, sparingly: `move = nil #: untyped` (a trailing type
   assertion) when flow analysis over unknown constants narrows a local too
   hard. RuboCop is configured to leave `#:` comments alone
   (`Layout/LeadingCommentSpace: AllowRBSInlineAnnotation`).

## The shims (`sig/`)

Hand-written, deliberately minimal — only what the actions layer actually
calls. Grow them method-by-method; never bulk-generate.

| File | Declares | Why |
|---|---|---|
| `sig/dry_monads.rbs` | Generic `Result`/`Success`/`Failure`, the `Success()`/`Failure()` constructors on `BaseAction`, `Dry::Monads.[]` | No community RBS for dry-monads; `include Dry::Monads[:result, :do]` is a dynamic call RBS can't model (`@rbs skip` on the include, surface declared here) |
| `sig/active_support.rbs` | `Time.current` | A **known** receiver + unknown method is a hard `NoMethod` error (unlike unknown constants, which degrade). Every ActiveSupport core-ext used on a known type in scope must be declared here |
| `sig/search_reindexing.rbs` | `Search::Reindexing` mixin surface | Pack-owned module included by `Boxes::Update`; the pack is outside the check scope. Delete when `packs/search` gets its own target |
| `sig/default_vocabularies.rbs` | `Moves::DefaultVocabularies.*` singleton methods | Inline RBS can't declare `def self.` yet |

## What the checker actually catches (honesty section)

**Caught:** wrong arity/kwargs against any annotated method (including every
`Success`/`Failure` call), a step method whose body can't produce its declared
return type, `NoMethod` on known types, literal-type inference errors (a
symbol-keyed hash literal indexed with a string — a real mixed-key bug this
adoption found in `Moves::SetRecognitionProvider#persist` before a single
annotation was written).

**Not caught (accepted, structural):**

- **Do-notation `yield` unwrapping is `untyped` by construction.**
  `Dry::Monads::Do` re-invokes `call` with an implicit unwrap block —
  metaprogramming Steep can't model. Each step method's declared contract is
  checked; the hand-off between steps is not. Don't oversell this: "each
  rail's shape is checked, the coupling between rails is not."
- **Cross-model mix-ups** (passing a Box where a Move is expected) — domain
  types are `untyped` until models get signatures.

## Growth roadmap (documented triggers, not speculation)

| Trigger | Action |
|---|---|
| A pack's actions get annotated | Add `check "packs/<name>/app/actions", inline: true` to the target; delete any shim the pack now declares inline (`sig/search_reindexing.rbs` first) |
| Real model types wanted (cross-model mix-ups start hurting) | Adopt `rbs_rails` (generated model sigs, needs DB — pair with the `packwerk` CI job the way structure.sql freshness works) and/or `rbs collection` (community gem sigs; commit `rbs_collection.lock.yaml`, gitignore `.gem_rbs_collection/`; beware activesupport sigs lag Rails 8.1) |
| An ActiveSupport core-ext on a known type blocks an annotation | Add the one method to `sig/active_support.rbs` |
| rbs/steep ship inline `def self.` support | Fold `sig/default_vocabularies.rbs` back into inline annotations |
| Steep's inline mode supports multiple targets over one tree | Optionally split strict/lenient targets (Steep 2.0.0 crashes on this today: "Source already exists" + deadlock) |

## Version coupling

`rbs` and `steep` are pinned in the Gemfile and must be **bumped together**
(the inline parser lives in rbs; Steep bundles against it). CI installs them
via `bundler-cache` — never `gem install` — so the checked versions are the
locked ones.

_Last updated: 2026-07-03 (#515 — initial adoption)._
