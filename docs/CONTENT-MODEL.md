# Content Model

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
content, NOT standalone published pages) — **except `media`, which is
`output: true`**; see "Media items are real pages" below. The layout reads each
as `site.<collection> | sort: 'weight'`:

| Collection | Directory | Per-item fields |
|------------|-----------|-----------------|
| `expertise`       | `_expertise/`       | `title`, `description`, `weight` |
| `experience`      | `_experience/`      | `title`, `org`, `period`, `description`, `weight` |
| `accomplishments` | `_accomplishments/` | `title`, `text`, `weight` |
| `media`           | `_media/`           | `category`, `title`, `source`, `article_url`, `pdf` (optional), `weight` |
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

### Media items are real pages, and NEVER use a front-matter `url:`

`media` is the one folder collection with **`output: true`**. Each item
publishes to `/media/<slug>/` via `_layouts/media.html`, and that page — not
the third-party site — is what the home page's media list links to. It carries
the item's optional archived **`pdf`** next to the outbound **`article_url`**.

This is not a styling preference; it is forced by a Jekyll trap that cost this
site every single media link:

- `_layouts/home.html` renders each link as `{{ item.url }}`. For a collection
  **document**, `url` is the document's **own address** — `Jekyll::Drops::
  DocumentDrop` defines `url`, and a Drop resolves its defined methods **before**
  falling back to front matter. A front-matter `url:` key is therefore
  **unreachable from Liquid**: `{{ item.url }}` and `{{ item['url'] }}` both
  yield `/media/<slug>/`. There is no accessor that reaches past it.
- With the collection at `output: false`, that address was never written, so
  **all 16 media links 404'd** — verified against preview-pr176 before the fix.
  Nothing failed the build; the gate (`site_live: false`) had simply hidden the
  section until go-live, so nobody had clicked one.

So: **the outbound link lives in `article_url`.** `admin/collections.site.yml`
names that field, so Decap writes it; `scripts/verify-build-artifacts.rb` fails
if any `_media/*.md` regains a top-level `url:` key, if an item stops resolving
to a built page, or if the admin seam loses the PDF widget. The same trap
applies to any new field you add here — check the name against `DocumentDrop`
(`url`, `content`, `output`, `path`, `relative_path`, `date`, `collection`,
`excerpt`, `id`, `next`, `previous`) before using it.

**PDF uploads use the site-wide media folder.** The `pdf` field is a plain
Decap `file` widget with no per-field `media_folder`/`public_folder`. The
platform's `config.base.yml` documents `public_folder == "/" + media_folder` as
an invariant enforced by `e2e/cms-config.spec.js` — Decap appends only the
uploaded basename to `public_folder` and does not mirror subdirectories into the
URL, so a per-field override reintroduces the broken-path / "Copy Path" bug.
Uploads land in `assets/images/uploads/` alongside the profile photo.

**Gating.** `_layouts/media.html` honours `site_live` exactly as `home.html`
does: while the gate is closed an item page renders only the coming-soon shell,
skips `{% seo %}` (so no article title reaches `<title>`/`og:title`/JSON-LD) and
is `noindex,nofollow`. `_config.yml` also sets `sitemap: false` for the whole
collection — unconditionally, because front-matter defaults can't read the gate
and the slugs are title-derived. The pages stay crawlable through the home
page's links once the site is live.

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

### Visual-regression gotchas (new sections / site-owned collections)

Footguns that bit adamdaniel.ai's Tools section rollout (fixed in
cms-platform#146) — check these before adding any new folder collection or
top-level route to this site:

- **The media item pages are exactly this case.** Turning `media` to
  `output: true` added 16 brand-new routes under `/media/`, so the PR that did
  it needed a one-time human regression approval.
- **New-section pages and the gate.** The regression page universe is a scan
  of the built `_site/`, so a new site-owned collection is covered
  automatically — nothing to wire — and a brand-new page is confirmed by prod
  answering 404/410 at capture time, scored "new", and routed through the
  manual `regression-review` gate. **Expect the first PR adding a new
  section's pages to force a one-time human regression approval — expected,
  not a failure.**
- **Sub-threshold and below-the-fold changes don't move the pixel diff.** The
  pixel gate ignores diffs under 0.5% of the viewport. The visible-text check
  closes this gap: a whitespace-normalized text delta escalates a
  pixel-"identical" page to review regardless of pixel count, and covers
  below-the-fold content the 1920×1080 screenshot never captures. Don't
  reason from pixel thresholds alone.
- Salience (which diffs are worth a human look) is decided entirely in the
  platform's `e2e/visual-regression-salient.js` — **not** by any caller-level
  `paths:` filter; `.github/workflows/visual-regression.yml` here intentionally
  fires on every PR.
