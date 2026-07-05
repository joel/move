# Self-Healing Infrastructure (Loop A)

Sentry → GitHub issue → agent fix PR → confidence-gated auto-merge → deploy →
post-deploy verification. This document is the operating manual for the
automated error-remediation pipeline: what each stage does, the safety
engine that governs autonomy, the manual setup it needs, and the runbooks
for pausing, recovering, and rolling back.

**Status: incremental rollout.** Stages land in order (release finalization →
scorer → triage → fix/score → steward → post-deploy verification); each
section below states which workflow/job implements it. Autonomy (auto-merge)
is OFF until the canary drill (§ Setup) passes and the
`SELF_HEALING_AUTONOMY_ENABLED` repo variable is set.

## Release tracking (already live — zero app code)

Prod Sentry events are tagged `release=<deployed git SHA>` without any app
configuration:

- Kamal injects `KAMAL_VERSION=<full git SHA>` into the app container
  (`kamal-2.12.0/lib/kamal/commands/app.rb:24`).
- sentry-ruby's `ReleaseDetector` auto-detects `ENV["KAMAL_VERSION"]` when
  `config.release` is unset (`config/initializers/sentry.rb` deliberately
  leaves it unset).

A dedicated **`Sentry Release` workflow**
(`.github/workflows/sentry-release.yml`, `workflow_run` on a successful
Deploy) finalizes each release: SHA-pinned `getsentry/action-release`
creates the release for the deployed SHA, associates commits from a
full-history checkout, and marks a `production` deploy. A separate workflow
on purpose: it must not hold the Deploy workflow's `deploy-production`
concurrency lock (best-effort Sentry bookkeeping must never delay a queued,
possibly urgent deploy), and the third-party action must never run in the
deploy job, whose env carries the full production secret set — here it sees
only the Sentry token + slugs. Unprovisioned credentials skip the steps
explicitly; a real Sentry failure turns only this workflow red, never the
deploy. Finalized releases + deploys are what make Sentry's `is:regressed`
query and suspect-commit attribution trustworthy for the pipeline.

**Verify** (one-time, and after Sentry/Kamal upgrades): open any recent prod
event in Sentry → the `release` tag equals the SHA of the currently deployed
merge commit; the release page shows commits and a production deploy.

## Pipeline overview

```
Sentry (prod errors, PII-scrubbed at ingest — config/initializers/sentry.rb)
  │ cron */30 poll (self-healing.yml `triage`)
  ▼
triage: kill switch + circuit breaker + dedupe + caps → public-safe GitHub issue
  ▼
fix:    whitelist-scrubbed event context → claude-code-action (failing spec →
        minimal fix) → assessment.json → App-token push → PR "Closes #N"
  ▼
score:  deterministic scorer FROM MAIN (script/self_healing/score.rb)
        → autofix:auto-eligible | autofix:needs-human + breakdown comment
  ▼
steward (later cycles): budget → deploy green → checks green → Codex verdict
        → update-branch if behind → direct squash merge → Sentry resolved
  ▼
deploy.yml (existing push-to-main deploy) → production
  ▼
verify: new events on the Sentry issue after the deploy completed?
        ⇒ reopen the GitHub issue + open a `self-healing-halt` issue (breaker)
```

Separation of duties: **Claude** (claude-code-action) writes the fix; **Codex**
(`chatgpt-codex-connector[bot]`) independently reviews it; a **deterministic
Ruby scorer** — always executed from `main`, never from the PR head — decides
whether the change is even eligible for autonomy; the **steward** merges only
when every gate agrees. The agent never holds push credentials; a GitHub App
token is minted by a deterministic workflow step after the agent finishes.

## Safety engine (summary)

- **Kill switch**: repo variable `SELF_HEALING_ENABLED` — anything but `true`
  makes every job a no-op.
- **Autonomy switch**: repo variable `SELF_HEALING_AUTONOMY_ENABLED` — the
  steward (auto-merge) additionally requires it. Everything upstream (issues,
  fix PRs, scoring) can run for calibration with autonomy off.
- **Circuit breaker**: an open issue labelled `self-healing-halt` stops the
  pipeline. Opened automatically by post-deploy verification on a suspected
  bad fix; closed manually after triage.
- **Blast radius**: `.github/autofix/blast_radius.yml` deny/allow path lists.
  Deny-listed paths (migrations, config, `.github/**`, `script/**`, auth/
  tenancy packs, JS/assets — untestable under `rack_test`) force the human
  path.
- **Hard gates + score**: `script/self_healing/score.rb` — deny paths, spec
  evidence, skip-marker regex, assessment integrity, size caps; then
  `S = 0.45·C_agent + 0.25·size + 0.20·spec_quality + 0.10·locality`,
  auto-eligible iff `S ≥ 85` and `C_agent ≥ 70`.
- **Budgets**: ≤2 fix candidates per cycle, ≤3 open autofix PRs, ≤3 automated
  merges per 24 h, one steward merge per cycle.
- **Public-repo doctrine**: everything the pipeline writes to public sinks
  (issues, PRs, logs) is non-sensitive **by construction** — the whitelist
  fetcher (`script/self_healing/sentry_fetch.rb`) reduces Sentry events to
  exception class/frames/transaction/counts; exception *messages* and
  breadcrumb values never reach the agent prompt or any public sink (they are
  attacker-influenceable → prompt-injection and PII channels). See
  `security-model.md`.

## Label state machine

| Label | Lives on | Meaning |
|---|---|---|
| `autofix` | issue + PR | Created/managed by the pipeline. |
| `sentry:<shortId>` | issue + PR | Binds them to one Sentry issue; the all-states dedupe key. |
| `autofix:attempted` | issue | A fix attempt ran (set BEFORE the agent runs — the retry-loop guard). Remove it to consciously allow a retry. |
| `autofix:auto-eligible` / `autofix:needs-human` | PR | The scorer's verdict, re-derived every cycle with an upserted breakdown comment. |
| `self-healing-halt` | issue | Circuit breaker: while one is open, every stage no-ops. Close after triage to resume. |

## Fix attempt lifecycle

1. `select` picks up to 2 open, unattempted `autofix` issues.
2. `fix` (per issue, matrix): labels the issue `autofix:attempted` first, checks
   out `main` with **no persisted credentials**, boots the CI Postgres service,
   stages whitelist-reduced context (`tmp/autofix/issue.md`, `event.json`), and
   runs `claude-code-action` with `.github/autofix/fix-prompt.md` — strict TDD
   (failing regression spec first), house conventions, path/size constraints,
   an honesty-calibrated `assessment.json`, and **no push/gh/network tools**
   (`--max-turns 40`, 30-minute timeout).
3. Deterministic post-steps validate (commits exist, assessment well-formed,
   `fixable: true`) and only then mint the App token, push
   `fix/sentry-<shortid>`, and open the PR (`Closes #<issue>`, assessment
   embedded in an HTML comment for the scorer). A failed attempt is reported on
   the issue instead — nothing is pushed.
4. `score` re-scores **every** open autofix PR from `main` each cycle:
   hard gates + weighted score → labels + a transparent breakdown comment.

Until the steward exists (and its canary passes), nothing merges — scored PRs
wait for a human, which doubles as the scorer's calibration window: compare
`autofix:auto-eligible` labels against what review actually found before
enabling autonomy.

## Manual setup checklist

One-time provisioning, in order:

1. **GitHub App `move-autofix`** — permissions: Contents RW, Issues RW,
   Pull requests RW; no webhook; installed on `joel/move` only.
   - Actions secrets `AUTOFIX_APP_ID`, `AUTOFIX_APP_PRIVATE_KEY` (CI-only,
     NOT Doppler-synced — same pattern as `CODEX_OPENAI_API_KEY`).
   - The same two values ALSO as **Dependabot secrets** — the dependabot
     auto-merge workflow runs on dependabot-triggered events, which read the
     Dependabot secrets store, not Actions secrets.
2. **Sentry internal integration** (Issue & Event Read/Write, Project Read)
   → Actions secret `SENTRY_AUTOFIX_TOKEN`. Smoke-test before enabling
   triage:
   ```bash
   # list candidate issues
   curl -sS -H "Authorization: Bearer $SENTRY_AUTOFIX_TOKEN" \
     "https://sentry.io/api/0/projects/$ORG/$PROJECT/issues/?query=is:unresolved+level:error&statsPeriod=24h" | jq 'length'
   # latest event for an issue
   curl -sS -H "Authorization: Bearer $SENTRY_AUTOFIX_TOKEN" \
     "https://sentry.io/api/0/organizations/$ORG/issues/$ISSUE_ID/events/latest/" | jq .eventID
   # update status
   curl -sS -X PUT -H "Authorization: Bearer $SENTRY_AUTOFIX_TOKEN" \
     -H "Content-Type: application/json" -d '{"status":"unresolved"}' \
     "https://sentry.io/api/0/organizations/$ORG/issues/$ISSUE_ID/" | jq .status
   ```
3. **Sentry org auth token** (scope `org:ci`) → Actions secret
   `SENTRY_RELEASE_TOKEN`; repo **variables** `SENTRY_ORG_SLUG`,
   `SENTRY_PROJECT_SLUG`, `SENTRY_PROJECT_ID` (slugs are not derivable from
   the repo).
4. **Anthropic** → Actions secret `AUTOFIX_ANTHROPIC_API_KEY`, with a spend
   cap configured in the Anthropic console (API key, not subscription OAuth —
   unattended CI billing must be capped and attributable).
5. Repo variable `SELF_HEALING_ENABLED=true`; labels `autofix`,
   `autofix:auto-eligible`, `autofix:needs-human`, `self-healing-halt`
   (`sentry:<shortId>` labels are created lazily by triage).
6. Verify release tagging (§ Release tracking above).
7. **Canary drill — gates autonomy.** Using the App identity: open a trivial
   PR → confirm (a) the branch push triggers CI, (b) whether Codex reviews a
   bot-authored PR (and whether `@codex review` wakes it), (c) an App-token
   merge to main triggers CI + Deploy. Record the outcome here. Only then set
   `SELF_HEALING_AUTONOMY_ENABLED=true`.

| Canary check | Result | Date |
|---|---|---|
| App branch push triggers CI | _pending_ | |
| Codex reviews bot PR | _pending_ | |
| `@codex review` wakes Codex on bot PR | _pending_ | |
| App merge to main triggers CI + Deploy | _pending_ | |
