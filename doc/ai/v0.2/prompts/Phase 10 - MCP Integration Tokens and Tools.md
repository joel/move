# Phase 10 - MCP Integration Tokens and Tools

## Goal

Add per-Move MCP integration tokens and the initial assistant tool surface.

By the end of this phase, a Move admin can create/revoke a token, and an MCP client can search, inspect boxes, add items/media, move items, mark unpacked, and get volume summary through shared domain actions.

## Depends on

- Phase 09 complete.

## Out of scope

- Telegram, WhatsApp, or any messaging client.
- Org-wide MCP API keys.
- Public unauthenticated API.
- Separate business logic for MCP.

## Main tasks

- Keep all new customer/UI-facing strings in YAML I18n files.
1. Create MoveIntegrationToken model if not already created.
2. Add token creation UI in Settings / Assistant area.
3. Show raw token only once.
4. Add token revoke action.
5. Update MCP authentication to resolve token to one Move.
6. Set Current context for MCP: organization, move, source `mcp`, actor/integration identity.
7. Add MCP base tool guard helpers.
8. Implement `search_items` tool.
9. Implement `get_box_contents` tool.
10. Implement `list_boxes` tool.
11. Implement `add_item_to_box` tool.
12. Implement `add_media_to_box` tool for image media and recognition enqueue.
13. Implement `move_item` tool.
14. Implement `mark_unpacked` tool.
15. Implement `get_volume_summary` tool.
16. Ensure all tools call shared actions.
17. Add audit entries for MCP mutations.
18. Add rate-limit or abuse guard if shell already has a pattern.

## Token rules

- Token scoped to exactly one Move.
- Token revocable independently from memberships.
- Token may mutate.
- Revoked token fails safely.
- Token cannot access other Moves or Organizations.
- Audit source is `mcp`.

## Tool rules

- `search_items`: confirmed active item search using Phase 07 search action.
- `get_box_contents`: returns authorized box listing.
- `list_boxes`: returns boxes for token Move.
- `add_item_to_box`: creates manual item via shared action.
- `add_media_to_box`: attaches image media and queues recognition.
- `move_item`: moves item to another box in same Move.
- `mark_unpacked`: marks item removed or box unpacked, depending on tool contract.
- `get_volume_summary`: returns Phase 09 summary.

## Tests

- Admin can create/revoke token.
- Contributor/viewer cannot create token.
- Raw token shown only once.
- Token digest stored, not raw token.
- Token resolves one Move.
- Token cannot access another Move in same Organization.
- Token cannot access another Organization.
- Revoked token rejected.
- Each tool calls shared action path.
- Mutating tools create audit rows with source `mcp`.
- MCP add_media_to_box queues recognition.

## Runtime verification

- Create token for a Move.
- Call list boxes.
- Call search items.
- Add item to box through MCP.
- Upload/add image media through MCP if test harness supports it.
- Move item through MCP.
- Mark item/box unpacked through MCP.
- Revoke token and verify calls fail.

## Acceptance criteria

- MCP surface is per-Move and revocable.
- No org-wide token remains for domain access.
- MCP tools cannot bypass authorization, actions, audit, or tenant scoping.
- Messaging channels remain out of scope.

## Suggested issue title

`Phase 10: Add per-Move MCP tokens and assistant tools`

## Suggested branch

`feature/phase-10-mcp-tools`
