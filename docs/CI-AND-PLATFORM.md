# CI and Platform

## CI: the e2e lane surfaces many contexts but requires ONE

`e2e-tests.yml` here is a thin caller; the platform reusable fans the Playwright
suite out over a **`project` matrix — one job per Playwright project** (10 of
them, each on its own runner, each installing only its own browser engine)
behind an aggregating `e2e` gate job. So a PR shows ~10 informational
`e2e / project (<name>)` checks plus the ONE required `e2e / e2e`, which is the
gate. No ruleset names the per-project contexts, and nothing in this repo needed
changing for it.

Most of those jobs are nearly empty here: `cms.base_collections: []` means the
generic-collection specs self-skip (see the platform's #33 guard registry), so a
single-page bio exercises far fewer tests than a full consumer.

Every project job runs at the SAME worker count (`150%` — 6 on a 4-vCPU runner);
an earlier version of this line said the counts "differ per project by design",
which was never true of the shipped config. `--shard` is deliberately unused (it
balances by test count, and per-test durations span 5 ms → 49 s) — the
measurements are in the platform's
[`docs/E2E-PARALLELISM.md`](https://github.com/Adam-S-Daniel/cms-platform/blob/main/docs/E2E-PARALLELISM.md).
To dial the workers down without a platform release, pass the reusable's
`workers` input from this caller (e.g. `workers: "2"`).

**Expect ~150-210 s**, not a single number: three consecutive bump PRs of the
same suite measured 148 s, 150 s and 210 s. The spread is per-lane browser-install
variance (this repo's `webkit-iphone16` install ranged 29-61 s) plus runner
allocation, not test time — so a 20% swing between two runs is not a regression.
`webkit-iphone16` is the long pole here too (190 s on the v0.1.70 bump: 61 s
install + 99 s tests), because WebKit runs the `@admin-read` specs several times
slower than Chromium does.

## Platform v0.1.76 — what changed for this repo

- **The 9 PR-triggered callers no longer fire on `pull_request: edited`**
  (`dependabot-auto-merge`, `deploy-preview`, `e2e-stub`, `e2e-tests`,
  `parity-preview`, `platform-pin-consistency`, `preview-media`, `secrets-scan`,
  `visual-regression`). A caller that skips emits **no check-run at all**, so an
  `edited` run WITHDRAWS a context an earlier run already reported green, and
  only a new SHA restores it — which a finished automated PR (a bump) never
  gets. The per-job `if:` that used to narrow `edited` to
  base retargets went with it. **`deploy-preview` keeps `closed`**: the
  reusable's teardown job fires only on that action (S3 `rm --recursive` +
  CloudFront invalidation + the preview bot-comment update), so dropping it
  would leak every closed PR's `pr-N/` prefix with no red check to show it.
- **The scheduled-run health audit no longer alerts on runs that never got a
  runner** — and this repo is where the class was found. All four 2026-08-06
  failures on tracking issue **#105** (`cms-automerge-nudge` ×2,
  `cms-media-roundtrip`, `publish-scheduled-posts`) were runner starvation: the
  job cancelled with `runner_id: 0` and an empty `runner_name`, ~15m02s from
  creation to cancellation, no steps run. Over a 168h window our alertable count
  goes **5 → 1**; the survivor is the genuine #220 stale-`platform_ref` failure
  (run 31242320695), which still alerts. #105 had already auto-closed on
  2026-08-10, so this is **prevention, not a repair** — the audit will open a
  FRESH issue on the next starvation event rather than reopening #105.
- **The loop deploy diagnostic gained merge-aware verdicts.** When a canary URL
  never reflects and the PR simply has not merged yet, it now reports
  `pr-awaiting-required-check` / `pr-required-check-red` (naming the check) and
  waits the merge out, instead of blaming the deploy chain. So an **older log
  line reading "NO deploy-production run fired … the chain never fired" is not
  evidence of a trigger problem** — before this fix a merely-slow auto-merge
  produced exactly that message. `no-deploy-fired` is still emitted, but only
  once the PR really has merged.

## Resolved blockers (historical)

Previously tracked in "Known open blockers (CMS editing)" in AGENTS.md;
all three are resolved.

- ~~**#27 — saving fails: org OAuth App access restrictions.**~~ **RESOLVED.**
  Login worked, but the `jodidaniel` GitHub **org** had OAuth App access
  restrictions on and the CMS OAuth App (Client ID `Ov23li6Nb58IZi6Nj5SY`)
  wasn't approved for the org, so Decap could authenticate (read) but
  **couldn't persist** ("Failed to persist entry: API_ERROR … OAuth App
  access restrictions"). An **org owner** approved the app (Settings →
  Third-party access) — saving from `/admin` now works (login + persist both
  succeed). adamdaniel never hit this (it's user-owned); jodidaniel was the
  first org-owned consumer. See #27.
- ~~**`CMS_E2E_PAT` repo secret not provisioned.**~~ **RESOLVED.** The secret
  is provisioned and the token-driven CMS automation reusables —
  `cms-automerge-nudge`, `auto-resolve-newline-conflict`, `sweep-stale-cms-prs`
  — are green. The sweep's earlier 30/30-failure streak was never a missing
  secret: it was a `cms-platform` bug where the sweep 404'd on this repo's
  missing `_e2e/`/`_posts/` directories (this single-page bio has neither),
  fixed upstream in cms-platform v0.1.49/v0.1.50 (PRs #127/#130 —
  "tolerate missing _e2e/_posts/uploads directories in consumers" /
  "discard gh api error-body stdout when directory listings fail"). Confirmed
  green on this repo after the bump.
- ~~**#28 — "Live Preview" 404s.**~~ **RESOLVED.** The site now ships
  `preview.md` (`layout: preview`, `permalink: /preview/`, mirroring
  adamdaniel.ai) + a friendly `404.html`, so the admin's Live Preview button
  reaches the gem's preview shell instead of a raw S3 `NoSuchKey`. The preview
  layout (shipped by `cms-platform-theme`, confirmed in the v0.1.7 pin) renders
  ONLY the empty preview chrome — no gated bio content; drafts stream in over
  `postMessage`/`BroadcastChannel` at edit time. `404.html` links back to `/`
  only (no `/blog/` — single-page bio) and is `noindex,nofollow`. Build
  verification: `bundle exec jekyll build && ruby scripts/verify-build-artifacts.rb`
  asserts `_site/preview/index.html` + `_site/404.html` exist, the preview is
  noindex and bio-free, and the 404 body links home not to a blog. See #28.
