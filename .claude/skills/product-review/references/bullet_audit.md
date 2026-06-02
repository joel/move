# Bullet N+1 Query Audit

If the project includes the `bullet` gem, it detects N+1 queries, unused eager loading, and counter cache opportunities. In development mode, Bullet is typically configured with:

- `alert = true` — JavaScript alert popup on every page with issues
- `add_footer = true` — HTML footer injected at the bottom of every page
- `console = true` — warnings logged to browser console
- `rails_logger = true` — warnings logged to Rails log

**On every page you visit during the review, you MUST check for Bullet alerts.** Bullet alerts are N+1 query problems that degrade performance and must be fixed before merge.

## How to Check for Bullet Alerts

After loading each page, run:

```bash
# Check for Bullet footer in page HTML
agent-browser eval "document.getElementById('bullet-footer')?.innerText || 'No Bullet warnings'"

# Check for Bullet alerts in browser console
agent-browser eval "window.__bullet_alerts || 'No alerts'"
```

Also check the Docker logs after browsing:

```bash
docker logs <app-container> --tail 100 2>&1 | grep -i "bullet\|USE eager\|N+1\|Counter cache"
```

## Common Bullet Findings and Fixes

| Bullet Message | Meaning | Fix |
|----------------|---------|-----|
| `USE eager loading detected: Model => [:association]` | N+1 query — each item triggers a separate query for the association | Add `.includes(:association)` to the controller query |
| `AVOID eager loading detected: Model => [:association]` | You're eager-loading an association that's never used on this page | Remove the `.includes(:association)` from the query |
| `Need Counter Cache: Model => [:association]` | Calling `.count` or `.size` on an association in a loop | Add `counter_cache: true` to the `belongs_to` or use `.size` with eager loading |

## Reporting Bullet Issues

List every Bullet warning in the report under a dedicated section:

```
## Bullet N+1 Alerts

| Page | Alert | Severity |
|------|-------|----------|
| /<index-page> | USE eager loading: <Model> => [:<association>] | Must fix |
| /<show-page> | None | Clean |
| /<nested-show-page> | USE eager loading: <Model> => [:<association>] | Must fix |
```

**Every "USE eager loading" alert is a defect that must be fixed.** Add `.includes(...)` or `.preload(...)` in the relevant controller action.

**"AVOID eager loading" alerts are warnings** — remove the unnecessary `.includes(...)`.
