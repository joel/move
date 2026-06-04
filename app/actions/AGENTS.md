# Actions Pattern (business logic layer)

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
- **Tests**: actions are plain Ruby — unit-test them directly with `.new.call(...)`
  and assert on `Success`/`Failure`.

## Adding an action

1. Create `app/actions/<domain>/<verb>.rb` inheriting `BaseAction`.
2. Implement `call(...)` chaining `persist` + `emit_event` with `yield`.
3. Emit a `domain.verb` event; register a subscriber if there's downstream work.
4. Call it from the controller and pattern-match the result.
5. Unit-test the action.
