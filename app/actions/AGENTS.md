# Actions Pattern (business logic layer)

> **Visual overview + onboarding:** [`README.md`](README.md) — diagrams of the
> request → action → event → subscriber flow, the Success/Failure railway, the
> worked example, and the **full event catalog** (which subscriber consumes each
> event). This file is the terse template/convention reference.

**All domain/business logic lives here — never in models or controllers.** Models
stay persistence-focused (associations, validations, scopes); controllers stay
thin (authorize → call action → pattern-match → render). This mirrors the
`catalyst` project's `app/actions` and https://github.com/joel/trip/tree/main/app/actions.

## Base class

```ruby
# app/actions/base_action.rb
class BaseAction
  include Dry::Monads[:result, :do]
end
```

Provides `Success(value)`, `Failure(value)`, and `yield` (unwrap a Success or
short-circuit on Failure — the railway pattern).

## Standard template

```ruby
# app/actions/moves/create.rb
module Moves
  class Create < BaseAction
    def call(params:, user:)
      move = yield persist(params, user)   # step 1: persist
      yield emit_event(move)               # step 2: emit event
      Success(move)                        # step 3: return
    end

    private

    def persist(params, user)
      Success(Move.create!(params.merge(created_by: user)))
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(move)
      Rails.event.notify("move.created", move_id: move.id)
      Success()
    end
  end
end
```

## Controller integration

```ruby
result = Moves::Create.new.call(params: move_params, user: current_user)

case result
in Dry::Monads::Success(move)
  redirect_to move, notice: t(".created")
in Dry::Monads::Failure(:some_rule)
  redirect_to moves_path, alert: t(".some_rule")
in Dry::Monads::Failure(errors)              # ActiveModel::Errors
  @move = Move.new(move_params)
  @move.errors.merge!(errors)
  render Views::Moves::New.new(move: @move), status: :unprocessable_content
end
```

## Conventions

- **One action per file**: `app/actions/<domain>/<verb>.rb` → `Domain::Verb`.
- **`call` takes named arguments**, returns `Success`/`Failure`.
- **Errors**: `Failure(e.record.errors)` for validations; `Failure(:symbol)` for
  business-rule violations; `Failure(:not_found)`; `Failure("message")`.
- **Events**: emit `domain.verb` via `Rails.event.notify` (Rails 8.1 structured
  events — subscribers respond to `#emit(event)`; see project `AGENTS.md`).
- **Delete**: capture ids before `destroy!` (the record is gone afterwards).
- **Guard + transition**: validate the business rule (`yield guard`) before the
  state change.
- **Archived-Move guard**: a user-facing *mutating* action's first step is
  `yield ensure_writable(<move>)` (`BaseAction#ensure_writable` → `Failure(:move_archived)`
  on an archived Move). This is the single source of truth for "an archived Move
  is read-only" — every caller (web, MCP, jobs) inherits it; controllers map the
  failure to a friendly redirect, MCP tools to a read-only tool error. Read-only
  actions (and token revoke) are not guarded.
  - **In-flight recognition on archive (#120, Option A):** because the guard
    writes *nothing* to a read-only Move, a recognition run queued before the
    Move was archived is left non-terminal (`queued`) rather than transitioned to
    a terminal state. This is intentional (zero writes on read-only) and
    invisible today (no archive UI; capture surface is gated by
    `require_writable_move!`). A future `Moves::Archive` action should cancel
    in-flight runs during the transition (while still writable).
- **Tests**: actions are plain Ruby — unit-test them directly with `.new.call(...)`
  and assert on `Success`/`Failure`.
- **Types**: every method gets an inline RBS annotation (`#:` on its own line
  directly above the `def`; domain objects are `untyped`, `call` returns
  `Dry::Monads::Result[untyped, untyped]`) — checked merge-blocking by Steep.
  Conventions + gotchas: [`doc/project/type-checking.md`](../../doc/project/type-checking.md).

## Adding an action

1. Create `app/actions/<domain>/<verb>.rb` inheriting `BaseAction`.
2. Implement `call(...)` chaining `persist` + `emit_event` with `yield`.
3. Annotate each method with its `#:` inline RBS type (see
   [`doc/project/type-checking.md`](../../doc/project/type-checking.md));
   `bundle exec steep check --no-daemon --severity-level=error` must stay green.
4. Emit a `domain.verb` event; register a subscriber if there's downstream work.
5. Call it from the controller and pattern-match the result.
6. Unit-test the action.
