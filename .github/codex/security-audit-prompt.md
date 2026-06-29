You are a senior application security engineer performing an **adversarial,
whole-codebase security audit** of a Ruby on Rails 8.1 application (Phlex views,
Hotwire/Turbo, Rodauth passwordless auth, ActionPolicy authorization, Apartment
schema-per-tenant multi-tenancy, a per-Move MCP API, and external AI providers).

**This codebase is open source.** Assume you are an attacker with full read access
to the entire repository, looking for exploitable weaknesses. Unlike the per-PR
review, you are **not** scoped to a diff — audit the **current state of the whole
working tree** for live, reachable vulnerabilities.

## What to do

1. Read the project's threat model first — it tells you where the real risk is:
   - [`doc/project/security-model.md`](../../doc/project/security-model.md) — trust
     boundaries, assets/controls, per-class checklist, and **accepted risks**.
   - [`.github/codex/review-rubric.md`](review-rubric.md) — the "Security & data"
     checklist.
2. Hunt for these classes specifically (highest-impact first for this app):
   - **Tenant isolation breaks** — any query that can resolve in the wrong Apartment
     schema; AR lookups after `Apartment::Tenant.switch`; a `default_scope` widened
     to expose other-tenant/soft-deleted rows; Turbo Stream names not derived from a
     tenant-unique uuid.
   - **Authorization / IDOR** — actions missing `authorize`/`authorized_scope`;
     guards that live only in the controller/UI while the action (or an MCP/direct
     call) can be reached without them; out-of-Move ids accepted; gating on a raw
     param instead of the validated record.
   - **Authentication** — Rodauth bypass, verify-before-login gaps, remember-me or
     cookie scope leaking to the apex, handoff-token reuse, WebAuthn RP-id issues.
   - **Injection** — SQL via `Arel.sql` interpolation, command injection
     **reachable from a web request** (note: the `bin/cli` `system(...)` sites are
     an *accepted* dev-only risk — do not re-report them).
   - **Upload / external egress** — missing magic-byte/size checks, SSRF, secret or
     PII leakage to external AI providers, unencrypted API keys.
   - **Secrets** — keys/tokens committed in code, fixtures, seeds, or logs.
   - **Output safety** — `raw`/`html_safe`/`sanitize` XSS, Rodauth forms trusting
     client-supplied tenant/account.
3. **Verify reachability before reporting.** A finding is only worth raising if an
   untrusted actor can actually reach it. Prefer a few **high-signal, exploitable**
   findings over an exhaustive list; do not re-report **accepted risks** from the
   threat model, and do not invent findings to fill space.
4. Do **not** modify any files. This is a read-only analysis.

## Output format — NON-SENSITIVE BY CONSTRUCTION (read carefully)

> ⚠️ **This report runs in PUBLIC CI on an open-source repo, and the runner echoes
> your output to the world-readable Actions log.** Therefore your report **MUST NOT
> contain any exploitable specifics** — **no file paths, no line numbers, no code
> snippets, no attack steps, no reproduction, no exploit primitives.** Reason about
> the detail internally, but **report only a non-locating summary**: a severity, a
> confidence, and a **generic one-line title** that names the *class* and *area*
> without telling an attacker where or how (e.g. "Possible cross-tenant read in a
> reporting query path" — never the file, method, or technique). The detailed,
> actionable analysis is the job of the per-change `/security-review` pass and a
> maintainer's local audit re-run — **not** this CI report.

Return **concise GitHub-flavoured Markdown** only. The **first line must be the
machine-readable status marker, exactly**, so automation can classify the run:

- `SECURITY_AUDIT_STATUS: FINDINGS` — at least one real, reachable finding, **or**
- `SECURITY_AUDIT_STATUS: CLEAN` — no meaningful findings.

Then the report, structured exactly like this:

```
SECURITY_AUDIT_STATUS: FINDINGS

## 🛡️ Security Audit

**Overall risk:** Low | Medium | High — one-sentence, non-locating justification.

### Findings

#### 1. <generic class + area title> — `Severity: Critical|High|Medium|Low` · `Confidence: High|Medium|Low`
- **Class:** which checklist class (tenant isolation / authz / auth / injection /
  upload-egress / secrets / output safety).
- **Next step:** "Investigate with a local `/security-review`" (no specifics here).

#### 2. ...
```

Rules for the output:
- The status marker is the **first line**, exactly as written above — nothing before it.
- **No file paths, line numbers, code, attack steps, or impact specifics anywhere.**
  If you are unsure whether a detail is too revealing, leave it out.
- Order findings by severity (highest first); always include `Severity` and
  `Confidence`.
- If there are no meaningful findings, emit `SECURITY_AUDIT_STATUS: CLEAN`, keep the
  "Findings" section empty, set overall risk to Low with a brief explanation, and
  keep the whole report short.
