# MCP Assistant (`app/mcp/move_mcp`)

> **Visual overview + onboarding:** [`README.md`](README.md) — the request lifecycle,
> auth/tenancy, the tool→action pattern, the tool catalog, and the Direct Upload
> handshake (all diagrammed). This file is the terse template/convention reference.

A stateless JSON-RPC endpoint (`POST /mcp`) exposing per-Move tools, on the official
`mcp` gem. **Tools own no business logic** — each resolves a Move-scoped record and
dispatches to a shared [`app/actions`](../actions/AGENTS.md). Auth = a per-Move Bearer
integration token; tenancy = the subdomain (Apartment elevator). The token is the
credential — no session, no CSRF (`ActionController::API`).

## How a request is served

`McpController#handle` (after `McpAuthentication`: 404 no tenant, 401 bad/revoked token)
sets `Current.move` + `Current.source = :mcp`, then
`MoveMcp::ServerBuilder.build(token:, base_url:)` → a fresh `MCP::Server` whose
`server_context` is `{ move:, token:, actor: token.created_by, base_url: }`. Every tool
reads that context.

## Tool template

```ruby
module MoveMcp::Tools
  class DoThing < Base                                  # < MCP::Tool
    tool_name "do_thing"
    description "One-line, model-facing description."
    input_schema(properties: { box_number: { type: "integer" } }, required: ["box_number"])
    # NB: never `required: []` — the gem rejects an empty required array.

    def self.call(box_number:, server_context:)
      record = find_box(server_context, box_number)      # Move-scoped lookup (Base helper)
      return error_response("No box ##{box_number} in this move.") if record.nil?

      result = ::Domain::Verb.new.call(... creator: actor(server_context))   # shared action
      return failure_response(result.failure) if result.failure?             # Failure → friendly copy

      audit(server_context, box_number: record.number.to_i)                  # → mcp.tool_called (mutations only)
      data_response(thing: thing_json(result.value!))
    end
  end
end
```

## `Base` helpers (`tools/base.rb`)

- **Context:** `move(ctx)` · `token(ctx)` · `actor(ctx)` (= `token.created_by`) · `base_url(ctx)`.
- **Lookups (Move-scoped, nil → caller returns error):** `find_box(ctx, n)` · `find_item(ctx, id)`.
- **Responses:** `text_response` · `data_response(data)` (text + `structured_content`) ·
  `error_response(msg)` · `failure_response(failure)` (symbol→copy map).
- **Audit:** `audit(ctx, **details)` → `MoveMcp::Audit.record` → `mcp.tool_called`.
- **Serialisers:** `box_json(box)` · `item_json(item)`.

## Conventions

- **One tool per file**, `move_mcp/tools/<name>.rb`, `class Name < Base`, `self.call(...)`.
- **Move-scoped only:** load every record through `move(ctx).boxes/.items` — never reach
  across Moves/Orgs (Apartment isolation is the second layer).
- **Reuse actions:** mutations go through the same `app/actions` as the web UI; the
  archived-Move guard (`ensure_writable → Failure(:move_archived)`), validations, tenancy
  and domain events come for free. Map the action `Failure` via `failure_response`.
- **Audit mutations:** call `audit(...)` after a successful mutating action; queries don't.
- **Attribution:** `actor = token.created_by` (domain events); `mcp.*` audit names the token.
- **Schemas:** declare an `input_schema`; omit `required:` entirely when there are no
  required args.
- **Register** every tool in `MoveMcp::ServerBuilder::TOOLS`.

## Adding a tool

1. `move_mcp/tools/<name>.rb` < `Base`; declare `tool_name` / `description` / `input_schema`.
2. `self.call`: Move-scoped lookup → shared action → `failure_response` → `audit` + `data_response`.
3. Register in `ServerBuilder::TOOLS`.
4. Spec it: `Tool.call(..., server_context: { move:, token:, actor: })`.

## Audit & uploads

- `mcp.tool_called` + `integration_token.{created,revoked}` → `MoveMcp::AuditSubscriber`
  (`config/initializers/mcp_audit.rb`, `AUDITED_PREFIXES = %w[integration_token. mcp.]`).
- **Direct Upload (#110):** `create_media_upload` → `POST /mcp/uploads`
  (`McpUploadsController`: magic-byte sniff `image/*` **excluding `image/svg+xml`**
  — SVG is markup, not a transcodable raster (#498) — ≤`Media::MAX_IMAGE_BYTES`,
  Move-scoped `signed_id`) → `add_media_to_box` → `Captures::Create`.
