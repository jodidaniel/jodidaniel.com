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
- **#27 — saving fails: org OAuth App access restrictions.** Login works, but
  the `jodidaniel` GitHub **org** has OAuth App access restrictions on and the
  CMS OAuth App (Client ID `Ov23li6Nb58IZi6Nj5SY`) isn't approved for the org,
  so Decap can authenticate (read) but **can't persist** ("Failed to persist
  entry: API_ERROR … OAuth App access restrictions"). Fix is an **org owner**
  approving the app (Settings → Third-party access) — not a code change.
  adamdaniel never hit this (it's user-owned). See #27.
- **#28 — "Live Preview" 404s.** The admin's Live Preview button opens
  `/preview/`, but this site has no `preview.md` page (nor a `404.html`). The
  gem ships the `preview` layout; the site must add `preview.md`
  (`layout: preview`, `permalink: /preview/`) + a `404.html`, mirroring
  adamdaniel.ai. See #28.

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
items by that `category` field and renders a per-category block with an icon —
so the on-disk subfolders under `_media/` (e.g. `_media/policy/`) are just
organization; grouping in the rendered page is driven by the `category` field,
not the subdirectory.

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
mark, not "AD". Verify: `bundle exec jekyll build && ruby scripts/verify-logo.rb`
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
