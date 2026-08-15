<!-- BEGIN MANAGED SECTION — DO NOT EDIT ABOVE "## Repo-specific additions" -->
<!-- Source: _agent-guidance -->
<!-- Sections: none -->

# AGENTS.md

> **Managed by [`_agent-guidance`].**
> Edit only below the `## Repo-specific additions` header.
> Everything above it will be overwritten on the next sync.

This block is deliberately short. It carries the things that are **specific to
this account and learned the hard way** — incidents, fleet policy, machine
layout. It does not restate general engineering practice, and it does not
describe anything you can learn by reading the repo. Depth lives in each repo's
`docs/` and in the skills registry; follow the pointers when the work touches
that area.

## Working in these repos

- Fix what was asked. No speculative features, premature abstractions, or
  unused helpers.
- Prefer editing an existing file over creating a new one.
- Every public interface change updates the corresponding tests.
- Run the existing test suite before calling a task complete, and say plainly
  what you ran. New behaviour gets a test; a bug fix gets a regression test.
- Tests must be deterministic — no sleeps, no network, no reliance on
  wall-clock time.

## Finding your unknowns

Output quality on a non-trivial task is bounded by how well the ambiguities got
resolved — and most of them surface *during* implementation, not before it. So
treat unknown-hunting as part of the work, not a phase that ends at the plan:

- Before building: name what you don't know. Prefer a reference in **code** — an
  existing implementation to mirror, a failing test, a rubric, an HTML mockup —
  over a prose description of the same thing.
- While building: keep a running note of decisions that departed from the plan
  and edge cases you hit. Surface them; don't silently absorb them.
- After building: be able to explain what changed and why it is correct.

The full workflow (blind-spot pass, self-interview, implementation notes,
post-hoc explainer) is the **`finding-unknowns`** skill in the registry. Reach
for it on unfamiliar code, a new domain, or anything with subjective acceptance
criteria.

## Workstation layout

Repo locations are host-specific — match the convention of the machine you're on
(on Windows, check `$env:COMPUTERNAME`).

- **`ZENDA`** (Windows): local clones live under `D:\repos\<github-owner-or-org>\<repo>`
  (for example `D:\repos\adam-s-daniel\wsl-automation`). Clone new repos there, and
  assume existing repos live there rather than under the user profile
  (`C:\Users\<user>\...`).

## Security

Standard practice applies without being restated here. These are the ones with
teeth in this account:

- Validate anything that crosses a trust boundary — user input, API responses,
  file contents.
- Never build SQL, shell commands, or HTML by string-concatenating untrusted
  data. Use parameterized queries, shell arrays, and context-aware escaping.
- Never commit secrets, credentials, or `.env` files.
- Never disable TLS verification, authentication, or CSRF protection.

## Data exposure in CI and public repos

Treat CI run logs, job summaries, artifacts, workflow run pages, and git history
as **public** on a public repo. (Real incident: a workflow printed the owner's
email addresses and their correspondents' into a public Actions log.)

- **Never print personal or sensitive data to a log** — no emails, contacts,
  names, IDs, mailbox sizes/counts, tokens, or anything "useful to an attacker or
  scammer." Deliver sensitive results out-of-band (e.g. email the account itself,
  write to a private store) and log only a non-identifying status line.
- **Don't interpolate `${{ inputs.* }}` / `${{ github.event.* }}` into a `run:`
  block** — the rendered command is echoed to the log. Read inputs from
  `$GITHUB_EVENT_PATH` inside the script and `::add-mask::` sensitive values
  before use. `::add-mask::` only scrubs the log *stream*, not other surfaces.
- **Put sensitive config in secrets, not plaintext inputs or `vars`.** Only
  secret *values* are masked in logs.
- **Sanitize error output** — never dump an API/HTTP response body on failure (it
  can quote personal data); reduce it to a status code + machine error type, and
  keep the data-bearing serialization/call inside the try/catch.
- **Least privilege:** set `permissions:` to the minimum (usually
  `contents: read`) and require approval for outside-collaborator fork PRs.
- **Test fixtures use reserved `example.com` / `example.net` domains only** —
  never a real address; fixtures get committed and logged.

### git history & metadata
- **Sanitize before the first commit.** Fixing the current file does not remove
  data from history. If sensitive data was committed, rewrite history to drop the
  commits, delete every ref that points at them (branches, tags, **PRs**), and
  force-push. GitHub garbage-collects unreachable objects on its own schedule
  (days to weeks) — until then they remain reachable *by SHA* — and you can ask
  GitHub Support to expedite for a public repo. (This is the deliberate exception
  to "don't force-push"; it is a security remediation.)
- **Commit with the GitHub `…@users.noreply.github.com` identity** on public
  repos so a real email is not baked into commit author/committer metadata.

## Automation vs branch protection

Fleet repos enforce PR-only default branches via ruleset, managed as code in
`repo-settings` (see its ADR 0001). Design automation accordingly:

- Never design a bot that pushes to a protected default branch ad hoc — the
  push is rejected (GH013), even from the repo's own workflows.
- Generated data (badges, run summaries, reports, dashboards) belongs on a
  dedicated unprotected results branch (e.g. skills-evals' `eval-results`);
  consumers read from that branch and treat its content as untrusted.
- The rare bot that genuinely must write to a default branch needs a ruleset
  bypass actor declared in repo-settings' `fleet.yml` — never a hand-granted
  UI bypass (the drift report flags those). The AGENTS.md sync App is the
  standing example.
- PR + auto-merge is not a sanctioned bot-write path for fleet repos; the
  cms-platform-managed repos (outside the fleet ruleset) use it by their own
  design.

## Dependency updates

Dependabot runs with a **minimum package age** (`cooldown`) so an unattended
merge still gets a cooling-off period: `default-days: 7`, `semver-major-days: 30`.
Two things about that setting are easy to get wrong:

- It applies to **version** updates only. A security advisory bypasses cooldown
  entirely and opens immediately — the wait never delays a vulnerability fix.
- An unset `cooldown` is **not** "no wait": GitHub applies an implicit 3-day
  minimum age to version updates. Writing 7 is a raise from 3, not from zero.

`semver-minor-days` / `semver-patch-days` are deliberately left undefined —
they fall back to `default-days`, and spelling them out only invites drift.
Pinning and bumping third-party action SHAs is the `pin-actions-to-sha` skill.

## Subagent delegation (model routing)

- Don't write code in the main loop: run the implementation in a subagent on an
  appropriately lower-power model (e.g. the Agent tool's `model` override in
  Claude Code; skip if the harness has no subagent support).
- Route by mechanicalness: smallest model (haiku-class) for exactly-specified
  edits — pin bumps, renames, config/doc tweaks; mid-tier (sonnet-class) for
  normal implementation from a clear spec. Escalate rather than ship a wrong
  diff when the task is genuinely subtle (cross-repo invariants, race
  conditions).
- The main loop keeps root-cause investigation, architectural decisions,
  writing the spec, and review of the subagent's diff before commit.
- Delegated work is done when a **verifier exits 0**, not when the report reads
  as finished. Name the exact command in the spec and require its exit code
  back. A subagent that cannot run it reports BLOCKED; a count that disagrees
  with the spec's stated expectation is a stop-and-report condition, never a
  rounding difference.
- Don't assume the subagent sees this file: general-purpose and custom
  subagents receive the full memory hierarchy (imports included), but
  Explore/Plan-type agents and SDK harnesses with `settingSources: []` skip
  repo guidance entirely. Restate load-bearing constraints (style, test
  command, invariants) in the delegation prompt, and don't hand
  guidance-sensitive work to agents that won't see it.

## Skills ecosystem

- The canonical skills registry is `github.com/Adam-S-Daniel/agentskills`,
  organized as three bundle plugins — `adam` (general-purpose, cloud-safe;
  default-on), `adam-local` (machine-bound), and `fastmail` — each holding
  `skills/<skill>/` directories.
- In Claude Code with the marketplace installed, invoke a skill as
  `/adam:<skill>` (e.g. `/adam:pin-actions-to-sha`).
- Local machines get the marketplace plus per-agent symlinks via that repo's
  `setup.sh`.
- Cloud/ephemeral sessions still get **no** plugins from repo-declared
  settings — that Claude Code limitation (agentskills' `docs/decisions/0001`)
  is unchanged. What changed is that it now has a fix: a repo carrying its own
  `skills.lock` plus the `skills-bootstrap` SessionStart hook installs the
  bundles that lock names directly into those sessions, verified against a
  pinned commit and per-skill digests. Such a session opens with a `skills:`
  verdict naming what loaded, or why nothing did — read it instead of guessing.
- **That adoption is opt-in and per-repo; most repos have not adopted.**
  Delivery is allowlisted in `_agent-guidance`'s `repos.yml` *and* requires the
  repo to have committed a `skills.lock` of its own first — the fleet sync
  never writes one, because the lock is each repo's own declaration of which
  bundles it installs (some federate several registries). So in an unfamiliar
  repo, look for `skills.lock` rather than assuming either way. Bundles cost
  always-on context in every session that carries them, which is why this is a
  deliberate per-repo decision and not a fleet default.
- New reusable skills graduate **into** the registry (sensitive ones into
  `agentskills-private`) rather than living on in a consumer repo. A long skill
  splits across files rather than growing into one wall of text.

## Git practices

- Write concise commit messages that explain *why*, not just *what*.
- One logical change per commit.
- Do not amend published commits or force-push shared branches.
- **Merge with a merge commit — `gh pr merge --merge`.** Squash and rebase are
  disabled on every fleet repo, so `--squash` fails rather than falling back;
  do not try it, and do not offer it as a choice. The exceptions are the three
  cms-platform-managed repos (`cms-platform`, `adamdaniel.ai`,
  `jodidaniel.com`), where squash stays enabled because the Decap publish chain
  arms SQUASH auto-merge on every editorial PR and squash is what collapses an
  editor's many per-save commits into one `publish: <title>` commit. Merge
  commits work there too, so `--merge` is the one form that works everywhere.

  Squash is off elsewhere because it is actively unsafe for a repo that pins
  commits by sha: it collapses a branch into a new commit and strands the
  originals on no branch, so a lockfile naming the pre-merge content commit
  (agentskills' `skills.lock`) ends up pinning something a fresh clone of the
  default branch does not contain. Measured on throwaway clones 2026-08-15 —
  `generate_skills_lock.py --check` then fails with `cannot resolve ref`.
  Settings are enforced as code: `repo-settings`' `fleet.yml` for the fleet,
  `cms-platform`'s `repo-settings.yml` for the three above.

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
