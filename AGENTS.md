<!-- BEGIN MANAGED SECTION — DO NOT EDIT ABOVE "## Repo-specific additions" -->
<!-- Source: _agent-guidance -->
<!-- Sections: none -->

# AGENTS.md

> **Managed by [`_agent-guidance`].**
> Edit only below the `## Repo-specific additions` header.
> Everything above it will be overwritten on the next sync.

## General guidelines

- Read existing code before modifying it. Understand the patterns already in use.
- Keep changes minimal and focused — fix what was asked, nothing more.
- Do not add speculative features, premature abstractions, or unused helpers.
- Prefer editing existing files over creating new ones.
- Never commit secrets, credentials, or .env files.

## Code quality

- Follow the idioms and style already established in this repo.
- Write code that is clear enough to not need comments; add comments only when intent is non-obvious.
- Avoid introducing new dependencies unless strictly necessary.
- Every public interface change should include corresponding test updates.

## Security

- Validate all external input (user input, API responses, file contents).
- Never construct SQL, shell commands, or HTML by string concatenation with untrusted data.
- Use parameterized queries, shell arrays, and context-aware escaping respectively.
- Do not disable TLS verification, authentication, or CSRF protection.

## Testing

- Run the existing test suite before considering a task complete.
- New behavior requires new tests; bug fixes require regression tests.
- Tests should be deterministic — no sleeping, no network calls, no reliance on wall-clock time.

## Subagent delegation (model routing)

- Don't write code in the main loop: run the implementation in a subagent on an
  appropriately lower-power model (e.g. the Agent tool's `model` override in
  Claude Code; skip if the harness has no subagent support).
- Route by mechanicalness: smallest model (haiku-class) for exactly-specified
  edits — pin bumps, renames, config/doc tweaks; mid-tier (sonnet-class) for
  normal implementation from a clear spec.
- The main loop keeps root-cause investigation, architectural decisions,
  writing the spec, and review of the subagent's diff before commit.
- Escalate the model rather than ship a wrong diff when the task is genuinely
  subtle (cross-repo invariants, race conditions).
- Don't assume the subagent sees this file: general-purpose and custom
  subagents receive the full memory hierarchy (imports included), but
  Explore/Plan-type agents and SDK harnesses with `settingSources: []` skip
  repo guidance entirely. Restate load-bearing constraints (style, test
  command, invariants) in the delegation prompt, and don't hand
  guidance-sensitive work to agents that won't see it.
- Give the subagent a precise spec — files, exact changes, house style, the
  test command to run. Subagent output is gated by the same test/CI proof as
  any other change.

## Git practices

- Write concise commit messages that explain *why*, not just *what*.
- One logical change per commit.
- Do not amend published commits or force-push shared branches.

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
(`platform_ref`); a Dependabot bundler bump of the `cms-platform-theme` gem (in
lockstep with the `uses:@` action pins) is the sync path. Do not vendor the
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

## Content model (per-section, all `/admin`-editable)

The home layout reads its copy from two kinds of source, NOT from a single
data file:

### Singleton sections → `_data/*.yml` (Decap *file* collections)

| Source file | Holds | Edited in `/admin` as |
|-------------|-------|------------------------|
| `_data/header.yml`   | `name`, `tagline`                              | **Header / Hero** (`site_header`) |
| `_data/about.yml`    | `photo`, `intro_heading`, `bio[]`, `nav[]`     | **About** (`site_about`) |
| `_data/contact.yml`  | `heading`, `intro`, `links[]`                  | **Contact** (`site_contact`) |
| `_data/settings.yml` | `site_live` GATE, `coming_soon`, `footer`, `section_headings` | **Site Settings** (`site_settings`) |

The layout reads these as `site.data.header` / `.about` / `.contact` /
`.settings`.

### Repeating sections → folder collections (one file per item, ordered by `weight`)

Declared in `_config.yml` `collections:` with **`output: false`** (editable
content, NOT standalone published pages). The layout reads each as
`site.<collection> | sort: 'weight'`:

| Collection | Directory | Per-item fields |
|------------|-----------|-----------------|
| `expertise`       | `_expertise/`       | `title`, `description`, `weight` |
| `experience`      | `_experience/`      | `title`, `org`, `period`, `description`, `weight` |
| `accomplishments` | `_accomplishments/` | `title`, `text`, `weight` |
| `media`           | `_media/`           | `category`, `title`, `source`, `url`, `weight` |
| `education`       | `_education/`       | `degree`, `field`, `school`, `weight` |

Each item is a front-matter-only `.md` file slugged `{{weight}}-{{slug}}`
(e.g. `_expertise/1-digital-health-ai.md`). `weight` controls render order.

**Media is special**: items carry a `category`
(Featured Articles / Policy & Advocacy / Podcasts & Interviews /
Speaking & Panels / Press & News). The home layout groups all `site.media`
items by that `category` field and renders a per-category block with an icon.
**Media item `.md` files live FLAT in `_media/` (no subdirectories).** They
used to be organized into category subfolders (`_media/policy/` etc.), but a
Decap **folder collection reads its `folder:` NON-recursively** — so the nested
files were invisible in `/admin` (the collection showed zero entries) even
though Jekyll's `site.media` reads them recursively and the live page rendered
fine. Grouping is by the `category` FIELD, never the path, so flattening is
loss-free; keep new items flat (Decap writes `{{weight}}-{{slug}}.md` into
`_media/`).

## `/admin` (Decap CMS)

`/admin` shows **9 per-section editors** — the 5 folder collections + the 4
file collections above — and **nothing else**. The generic platform
collections (posts / tags / projects / pages / e2e) are hidden by
`cms.base_collections: []` in `_config.yml` (an empty keep-list hides them all;
honored by `cms-platform-theme` >= v0.1.7). This single-page bio has no blog.

The admin UI itself is **delivered by the gem** (`cms-platform-theme`), not
vendored here. The only admin file this repo owns is the **site seam**
`admin/collections.site.yml`: a YAML fragment of Decap collection definitions
that the platform's render hook splices into the base config at the
`# __SITE_COLLECTIONS__` marker at build time (indentation must match the base
list — 2 spaces for `- name:`). `admin/collections.site.yml.example` documents
the seam format. Do not add a vendored `admin/config.yml` or admin machinery;
edit the seam and bump the gem.

**Brand mark (`/admin` + site logo).** The gem's render hook defaults the
admin's `logo_url` (`CMS_LOGO_URL`) to `<url>/assets/images/logo.svg` when
`cms.logo_url` is unset. The gem ships a placeholder `assets/images/logo.svg`
that is an **"AD" (Adam Daniel)** monogram — so a consuming site that ships no
logo leaks Adam's mark into its `/admin`. This repo therefore owns
`assets/images/logo.svg` — Jodi's own **"JD"** mark in her palette (teal accent
`#5dd9e8`, Raleway, matching `assets/css/jodidaniel.css`). The **site file
shadows the gem's** copy (Jekyll site files override theme-gem files), so
`/admin` and the rendered `_site/assets/images/logo.svg` resolve to Jodi's
mark, not "AD". Verify: `bundle exec jekyll build && ruby scripts/verify-build-artifacts.rb`
(asserts the rendered logo is the JD mark and `logo_url` points at the site
asset). Resolved #31.

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
- `/admin` = 9 section editors; generics hidden via `cms.base_collections: []`;
  admin UI shipped by the `cms-platform-theme` gem; seam =
  `admin/collections.site.yml`.
- `mockup.html` is the design reference (excluded from the build); live copy is
  verbatim from it.
- Go-live (flip the gate + restore SEO/title + headshot) is **issue #26**,
  pending boss copy sign-off. Do not leak bio content to prod before then.
