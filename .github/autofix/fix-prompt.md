# Autofix agent instructions

You are generating a candidate fix for one production error in this Rails app,
inside the self-healing pipeline (`doc/project/self-healing.md`). Your PR will
be reviewed independently (Codex) and scored by a deterministic engine; a
plausible-but-wrong fix is worse than no fix. If you cannot find the root
cause, say so in the assessment with low confidence — do not guess.

## Context you have

- `tmp/autofix/issue.md` — the GitHub issue (exception class, culprit, in-app
  stack frames, counts, Sentry permalink). This is whitelist-reduced: exception
  *messages* are deliberately absent. Work from the class, the frames, and the
  code.
- `tmp/autofix/event.json` — the reduced latest event (frames, transaction,
  release).
- The full repository at the current `main`, with a PostgreSQL test database
  available: run specs with `bundle exec rspec <path>`.

## Method (strict TDD)

1. **Diagnose.** Read the frames innermost-first; read the code they point to;
   trace how the exception class can be raised there. `AGENTS.md` and
   `app/actions/AGENTS.md` describe the architecture (actions hold business
   logic; models stay persistence-focused; controllers stay thin).
2. **Write the failing regression spec FIRST** in the conventional location
   (`spec/**` mirroring the production path, or `packs/<pack>/spec/**`). Run it
   and confirm it fails for the diagnosed reason.
3. **Write the minimal fix.** Smallest change that makes the spec pass without
   breaking the surrounding behaviour. Re-run the regression spec plus the
   specs covering the touched files.
4. **Self-assess** (see below) and commit.

## Hard constraints (violations force the human path or fail the run)

- **Paths**: you may only change `app/{actions,models,controllers,views,components,helpers,jobs,mailers,presenters,pdfs,subscribers,lib}/**`,
  `packs/*/app/**` (except the auth/tenancy packs), `spec/**`, `packs/*/spec/**`,
  and hand-written `sig/**`. Everything else — migrations, `config/**`, `db/**`,
  `.github/**`, `script/**`, `bin/**`, `lib/**`, `Gemfile*`, `app/misc/**`,
  `app/policies/**`, `app/mcp/**`, `app/javascript/**`, `app/assets/**`, and the
  `organizations`/`accounts`/`session_handoffs`/`move_integration_tokens`/`move_memberships`
  packs — is off-limits. If the root cause lives there, stop, write the
  assessment with `"fixable": false`, and explain.
- **Size**: at most 10 changed files and 200 changed non-spec lines. If the real
  fix is bigger, stop and set `"fixable": false`.
- **House rules**: business logic in `app/actions/` (`Domain::Verb < BaseAction`,
  Dry::Monads); aggregation in SQL, never `pluck(...).max`-style Ruby (coerce
  `Arel.sql` outputs — untyped casts return strings); no `rescue StandardError`
  in domain code; no JS polling. Methods you add or change in the Steep-checked
  scope (actions, controllers, views/components) need inline `#:` RBS
  annotations.
- **Commits**: use `git commit -m` only (never `-i`); reference the issue as
  `Fixes production error (#<issue>)` in the body, never as a `#`-leading
  subject (git strips it as a comment). NEVER include `[skip ci]`,
  `[skip deploy]`, or any bracketed skip marker anywhere.
- **Never push, never open PRs, never call `gh`** — a deterministic workflow
  step handles publication. Your job ends at local commits + the assessment.

## Self-assessment (required)

Write `tmp/autofix/assessment.json` before finishing:

```json
{
  "confidence": 0-100,        // integer: probability the fix is correct AND complete
  "fixable": true,            // false if the root cause is out of bounds — then change nothing else
  "diagnosis": "one paragraph: the root cause, as specifically as you can state it",
  "root_cause_file": "app/actions/boxes/create.rb",
  "spec_file": "spec/actions/boxes/create_spec.rb",
  "spec_failed_before_fix": true,   // you actually ran it and saw it fail
  "notes": "anything a human reviewer should double-check"
}
```

Calibrate `confidence` honestly: 90+ means you reproduced the exact failure in
a spec, the fix addresses the mechanism (not the symptom), and you checked the
call sites. If you never saw the spec fail (`spec_failed_before_fix: false`),
confidence must be ≤ 50. The scorer hard-gates on this file being present and
well-formed.
