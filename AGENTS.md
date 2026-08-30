<!-- BEGIN MANAGED SECTION — DO NOT EDIT ABOVE "## Repo-specific additions" -->
<!-- Source: _agent-guidance -->
<!-- Sections: none -->
<!-- Mode: stub -->

# AGENTS.md

> **Managed by [`_agent-guidance`].**
> Edit only below the `## Repo-specific additions` header.
> Everything above it will be overwritten on the next sync.

## Fleet guidance is delivered once per session — not by this file

The account's full guidance — incidents, fleet policy, machine layout, the
traps that cost real outages — is installed into **user memory**
(`~/.claude/CLAUDE.md`) by the `fleet-memory` SessionStart hook, so it is
loaded **once per session** no matter how many repos are attached. It used to
be inlined here in every repo, which meant a session with 19 repos open
carried 19 identical copies: 332.3k tokens of a 1M window, measured
2026-08-29.

**Check the session-start verdict before you rely on it.** The hook prints one
line:

- `fleet-guidance: installed (v<id>, <n> bytes)` or `fleet-guidance: current` —
  the full guidance is in context. Use it.
- `fleet-guidance: DEGRADED — <reason>` — it is **not** in context. You have
  only what is below. Read `agents-md/base.md` in the `_agent-guidance`
  checkout (or on GitHub) before non-trivial work, and say in your reply that
  you were running degraded.
- `fleet-guidance: skipped (FLEET_GUIDANCE_SKIP set)` — also not in context,
  but by the machine owner's deliberate choice, not a fault. User memory is
  GLOBAL on a durable machine, so the guidance would otherwise load in every
  unrelated project on that box; `FLEET_GUIDANCE_SKIP` opts out and removes any
  block an earlier session installed. Read `agents-md/base.md` the same way you
  would when degraded — just don't report it as a problem or try to "fix" it.

No verdict at all means the hook never ran — treat that as DEGRADED.

## The floor: rules that hold even when the guidance did not load

These are the ones with teeth. They are restated here, deliberately, because a
session that lost the guidance must not also lose these.

- **Branch protection is real.** Fleet repos are PR-only on their default
  branch; a direct push is rejected (GH013), even from the repo's own
  workflows. Never design a bot that pushes to a protected default branch.
- **Every `uses:` is pinned to a full 40-character commit SHA, with no
  trailing version comment.** The one carve-out is a ref into this account's
  own `cms-platform`, which stays on its release tag.
- **Never commit secrets or `.env` files, and never print personal data to a
  CI log** — logs, artifacts and git history on a public repo are public.
- **A successful `git push` does not mean your commit exists.** A refused
  pre-commit hook still lets the push report success. Verify with
  `git merge-base --is-ancestor <sha> origin/<branch>` — it is the only check
  that names both the commit and the ref.
- **"The watch finished" is not "CI passed."** Read the parsed conclusions;
  never infer pass/fail from a watch command's exit code.
- **A GitHub 404 means "not authorized", not "not there."** Never report a
  repo, PR or branch as gone on a 404 alone.
- **The fleet spans TWO owners** — `Adam-S-Daniel` and `jodidaniel`. A query
  scoped to one returns a plausible, complete-shaped, wrong answer.
- **Anything you name gets its link** — what you hand over, what you are
  waiting on, and what you cite as already done.
- **Merge with a merge commit** (`gh pr merge --merge`); do not amend
  published commits or force-push shared branches.

<!-- END MANAGED SECTION -->
## Repo-specific additions

# AGENTS.md

Guidance for AI agents working in this repository.

## About this repo

This is the personal/professional website for **Jodi Daniel**, a digital
health law and policy leader (partner at Wilson Sonsini; previously partner and
managing director at Crowell & Moring; founding policy director at ONC/HHS).

It is a **single-page gated bio** built on Jekyll and the
[`cms-platform`](https://github.com/Adam-S-Daniel/cms-platform) theme/CI. The
page is `index.html` (`layout: home` → site-local `_layouts/home.html`); its
copy comes from per-section data + collections (see below), all editable via
`/admin`. `mockup.html` is the **design reference** (the source-of-truth for
the home layout and `assets/css/jodidaniel.css`) — it is excluded from the
Jekyll build (`exclude:` in `_config.yml`), not a published page. All bio copy
on the live site is verbatim from `mockup.html`.

**Page-background gradient carries a noise DITHER overlay — do not remove it.**
`assets/css/jodidaniel.css` paints a 135° linear gradient on `body`; that
gradient BANDS on Firefox + WebKit (Chromium dithers CSS gradients, those
engines don't), which the platform `glow-banding` e2e catches. A near-invisible
(3.5% opacity) `feTurbulence` noise overlay on `body::after` (z-index:-1,
pointer-events:none — strictly behind content) scatters the banding so it reads
smooth on all engines. Same technique the platform theme uses. Removing it
re-reds `glow-banding` on firefox-desktop + webkit-tablet.

This site is **consumer #2** of `cms-platform` (after adamdaniel.ai). The
platform release this repo is pinned to is recorded in `platform.lock`
(`platform_ref`); the sync path is `platform-bump.yml`, which moves the
`cms-platform-theme` gem in lockstep with the `uses:@` action pins in one atomic
PR. Dependabot's `bundler` ecosystem `ignore`s that gem (cms-platform#242), and
its `github-actions` ecosystem ignores the `uses:@` pins the same way
(cms-platform#244) — either ecosystem could only move its own half and would
skew the pins. See cms-platform's `docs/SYNC.md` for the sync model. Do not vendor the
platform's `admin/` machinery — the gem ships it; this repo keeps only the
site-owned seam (`admin/collections.site.yml`).

## Name variants

Jodi Daniel appears under several name forms across public records, legal
filings, and bylines. Treat all of the following as referring to the same
person:

- **Jodi Daniel**
- **Jodi Goldstein Daniel**
- **Jodi G. Daniel**

For example, U.S. Supreme Court filings list her as counsel under
"Jodi Goldstein Daniel" — see the *Brief of Over 640 State Legislators as Amici
Curiae* in *FDA v. Alliance for Hippocratic Medicine* (No. 23-235), where she is
co-counsel with Crowell & Moring LLP. When evaluating whether a source relates
to her, check for these variants (including in counsel/signature blocks, not
just author bylines or named-party lists).

## The go-live gate (read this before touching content)

The whole site is **gated**: it ships coming-soon and stays that way until the
boss signs off on the copy. The gate is a single boolean,
**`site_live` in `_data/settings.yml`** (default `false`).

`_layouts/home.html` assigns `live = settings.site_live` and wraps **every** bio
section (about, expertise, experience, accomplishments, media, education,
contact) in `{% if live %}`. When `site_live` is `false`, only the coming-soon
shell renders: the name (`_data/header.yml`), `coming_soon.tagline`, and
`coming_soon.copyright` (all from `_data/settings.yml`). The full bio copy is
present in the data/collections but is **not rendered** — so there is zero bio
leak on prod while gated.

SEO is gated in parallel: `_config.yml` `description:` stays neutral
("…site coming soon."), and `index.html` sets **no page title** so `{% seo %}`
renders only the neutral site title — no marketing claim is served until
sign-off. Both `_config.yml` and `index.html` carry inline comments with the
real (post-go-live) values to restore.

**Go-live = issue #26**: flip `site_live: true` (via `/admin`), restore the real
`description:` in `_config.yml` and the real page title, and add the headshot —
after the boss approves the copy. Until then, no bio content reaches prod and
no marketing claim ships. Do not flip the gate on your own initiative.

### Known open blockers (CMS editing)

All three blockers previously tracked here (#27 org OAuth App access
restrictions, the `CMS_E2E_PAT` repo secret, #28 "Live Preview" 404s) are now
RESOLVED — see
[`docs/CI-AND-PLATFORM.md`](docs/CI-AND-PLATFORM.md#resolved-blockers-historical)
for the full history.

## Content model (per-section, all `/admin`-editable)

Per-section content sources: singleton `_data/*.yml` files (Decap file
collections) vs. per-item folder collections ordered by `weight`, their field
lists, and the flat-`_media/` (non-recursive folder collection) gotcha →
read [`docs/CONTENT-MODEL.md`](docs/CONTENT-MODEL.md) before adding, renaming,
or reshaping a content source.

## `/admin` (Decap CMS)

The 9 section editors, the site-owned `admin/collections.site.yml` seam
format, the brand-mark shadowing fix, and visual-regression gotchas for new
folder collections/top-level routes → read
[`docs/CONTENT-MODEL.md`](docs/CONTENT-MODEL.md) before touching `/admin`
config or adding a new section.

## CI: the e2e lane surfaces many contexts but requires ONE

The e2e matrix's per-project jobs, worker counts, expected wall-clock range
(~150-210s), and why `--shard` is unused → read
[`docs/CI-AND-PLATFORM.md`](docs/CI-AND-PLATFORM.md) before reasoning about a
red or slow e2e run.

## Platform v0.1.76 — what changed for this repo

The `pull_request: edited` trigger removal, the scheduled-run health audit's
runner-starvation fix, and the deploy-lane diagnostic's merge-aware verdicts
→ read [`docs/CI-AND-PLATFORM.md`](docs/CI-AND-PLATFORM.md) before treating an
old "chain never fired" log line as a trigger bug.

## OAuth (Decap editorial login)

The Decap GitHub backend authenticates through an **API Gateway OAuth proxy**:

- `_config.yml` `cms.oauth_base_url` → the proxy `ApiUrl`
  (`https://zkrofo300b.execute-api.us-east-1.amazonaws.com`); the rendered
  Decap config uses it as `backend.base_url` + the `prod/auth` auth endpoint.
- GitHub OAuth App callback = `<oauth_base_url>/prod/callback`.
- The proxy CloudFormation stack is `jodidaniel-com-oauth-proxy` (us-east-1);
  per-site deploy params (incl. the GitHub OAuth client id/secret) come from
  `infrastructure/site-params.env` (gitignored; copy from
  `infrastructure/site-params.example.env`). Login is working.

## Hosting / DNS

Production is served from CloudFront; the apex `jodidaniel.com` was cut over
from Squarespace to our CloudFront (apex A → alias). Coming-soon is live.

## Quick orientation for a fresh session

- Single-page gated bio. Gate = `_data/settings.yml` `site_live` (default
  `false`); `_layouts/home.html` wraps bio sections in `{% if live %}`.
- Content lives in `_data/{header,about,contact,settings}.yml` (singletons) +
  the `_expertise/_experience/_accomplishments/_media/_education` folder
  collections (ordered by `weight`, `output: false`). NOT a single data file.
  Full field lists → `docs/CONTENT-MODEL.md`.
- `/admin` = 9 section editors; generics hidden via `cms.base_collections: []`;
  admin UI shipped by the `cms-platform-theme` gem; seam =
  `admin/collections.site.yml`.
  Full detail → `docs/CONTENT-MODEL.md`.
- `mockup.html` is the design reference (excluded from the build); live copy is
  verbatim from it.
- Go-live (flip the gate + restore SEO/title + headshot) is **issue #26**,
  pending boss copy sign-off. Do not leak bio content to prod before then.
- CI/platform behavior (e2e matrix, platform version notes) → `docs/CI-AND-PLATFORM.md`.

## Deeper references

- [`docs/CONTENT-MODEL.md`](docs/CONTENT-MODEL.md) — read when adding, renaming,
  or reshaping a content source, or when touching `/admin` config or adding a
  new section/collection.
- [`docs/CI-AND-PLATFORM.md`](docs/CI-AND-PLATFORM.md) — read when triaging a
  red or slow e2e run, understanding what the platform v0.1.76 bump changed
  here, or looking up the history of a now-resolved CMS-editing blocker.

## Keep every visible string `/admin`-editable

- **New or changed on-page copy comes from a Decap-backed source — a
  `_data/*.yml` singleton or a `weight`-ordered folder collection — never a
  literal in `_layouts/home.html` or an include.** The premise of this site is
  that its owner maintains it end to end without a developer; a string only a
  commit can change is invisible in `/admin` and she cannot fix it herself. Add
  the data source first, then have the layout read it (`site.data.*` /
  `site.<collection>`), not the other way round. Even the five section headings
  live in `_data/settings.yml` `section_headings` for this reason.
- **A string you genuinely cannot route through `/admin` is a decision to
  surface, not a detail to absorb silently** — call it out in the PR and get it
  agreed before merge. Hardcoded chrome stays at the irreducible minimum.
- **The one standing exception is the media category list, and it lives in two
  places that must move together**: `media_by_category` in
  `_layouts/home.html` (drives grouping, order, and the rendered `<h3>` label)
  and the `category` select `options:` in `admin/collections.site.yml` (drives
  what the editor can pick). Adding, renaming, or reordering a category means
  editing BOTH — a value present in only one silently drops items from the page
  or from the picker, with no build error.
