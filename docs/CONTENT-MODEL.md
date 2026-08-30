# Content Model

## Content model (per-section, all `/admin`-editable)

The home layout reads its copy from two kinds of source, NOT from a single
data file:

### Singleton sections → `_data/*.yml` (Decap *file* collections)

| Source file | Holds | Edited in `/admin` as |
|-------------|-------|------------------------|
| `_data/header.yml`   | `name`, `tagline`                              | **Header / Hero** (`site_header`) |
| `_data/about.yml`    | `photo`, `intro_heading`, `lead`, `bio[]`, `nav[]` | **About** (`site_about`) |
| `_data/contact.yml`  | `heading`, `intro`, `links[]`                  | **Contact** (`site_contact`) |
| `_data/settings.yml` | `site_live` GATE, `coming_soon`, `footer`, `back_to_top_label`, `section_headings` | **Site Settings** (`site_settings`) |

The layout reads these as `site.data.header` / `.about` / `.contact` /
`.settings`.

### About nav anchors are a closed set (issue #196)

`_data/about.yml`'s `nav[]` pairs a `label` (the pill's visible text) with an
`anchor` (which section the pill jumps to) — two fields that look related but
aren't linked to each other at all. Before issue #196 `anchor` was free-text,
so a typo (e.g. `presss` instead of `media`) saved silently: the pill's `href`
changed the URL hash and nothing else happened, with no error anywhere to
explain why. The owner's experienced symptom was "I renamed a nav label and
now the button is dead."

`admin/collections.site.yml` now makes `anchor` a `select` over the six
sections in `_layouts/home.html` this nav can actually jump to. `about` is
deliberately excluded from the options: the nav list renders *inside* the
About card itself, so a pill pointing at its own container isn't a meaningful
destination.

**This options list is DUAL-MAINTAINED with `_layouts/home.html`**, exactly
like `media_by_category` there vs. the media `category` select `options:`
(see "Outbound link label + PDF button label" below): adding, removing, or
renaming a `<section id="...">` in the layout means editing this options list
too, or the new/renamed section becomes unreachable from the nav picker with
no build error.

A `select` only stops a *new* typo made through the UI. It does not catch a
bad anchor already committed, one introduced by a direct file edit, or a
section id renamed in the layout while `_data/about.yml` still names the old
one — the more likely real-world break, and the one a `select` alone can't
close. `scripts/verify-build-artifacts.rb` covers that gap: for every entry
in `_data/about.yml`'s `nav`, the *built* home page must contain a real
`<section id="...">` matching that entry's `anchor` — checked against
`_site/index.html`, not the layout source — so a rename that silently drifts
the two apart fails the build instead of shipping a dead pill. That check is
vacuous while `site_live: false` (the gate hides every section, so there is
nothing built to check anchors against); it prints a `note` saying so rather
than letting a pass imply coverage it doesn't have — the same conditional
posture as the PDF-upload checks documented further down in this file.

### Repeating sections → folder collections (one file per item, ordered by `weight`)

Declared in `_config.yml` `collections:` with **`output: false`** (editable
content, NOT standalone published pages) — **except `media`, which is
`output: true`**; see "Media items are real pages" below. The layout reads each
as `site.<collection> | sort: 'weight'` — **except `events`, sorted by
`start_date`**; see "Upcoming Events are ordered by `start_date`, not `weight`"
below.

| Collection | Directory | Per-item fields |
|------------|-----------|-----------------|
| `expertise`       | `_expertise/`       | `title`, `description`, `weight` |
| `experience`      | `_experience/`      | `title`, `org`, `period`, `description`, `weight` |
| `accomplishments` | `_accomplishments/` | `title`, `text`, `weight` |
| `media`           | `_media/`           | `category`, `title`, `source`, `article_url`, `link_label` (optional), `pdf` (optional), `pdf_label` (optional), `weight` |
| `education`       | `_education/`       | `degree`, `field`, `school`, `weight` |
| `events`          | `_events/`          | `title`, `org`, `start_date`, `date_display`, `location`, `session` (optional), `event_url` (optional) |

Each item is a front-matter-only `.md` file slugged `{{weight}}-{{slug}}`
(e.g. `_expertise/1-digital-health-ai.md`). `weight` controls render order.
**`events` is the one exception**: it is slugged `{{start_date}}-{{slug}}`
instead, because there is no `weight` field to slug from — see below.

### Upcoming Events are ordered by `start_date`, not `weight` (Jodi's 2026-08-30 feedback)

`events` departs from every sibling folder collection above in three ways,
each forced by what the section actually needs:

- **Ordered by `start_date`, not `weight`.** "Upcoming" is inherently
  chronological, so the date itself decides the order
  (`site.events | sort: 'start_date'` in `_layouts/home.html`) rather than a
  hand-maintained number. This is also what frees the owner from
  renumbering the whole list every time she inserts a new event between two
  existing ones — the trade-off every other section's `weight` field makes
  in the other direction (an explicit, editor-controlled order that has to
  be kept in sync by hand).
- **`start_date` must stay a quoted `"YYYY-MM-DD"` string, never a bare
  date.** Decap's `string` widget always writes a quoted scalar, so a
  Decap-saved value parses as a Ruby/YAML String. A hand edit that drops the
  quotes (`start_date: 2026-09-17`) gets auto-resolved to a YAML timestamp
  (a `Date` object) instead, and `sort: 'start_date'` on a mix of Strings
  and Dates compares mismatched types — `scripts/verify-build-artifacts.rb`
  asserts every `_events/*.md`'s `start_date` is a String matching
  `\A\d{4}-\d{2}-\d{2}\z` for exactly this reason. The admin seam's
  `pattern: ['^\d{4}-\d{2}-\d{2}$', ...]` on that field must also stay
  **single-quoted YAML** — `\d` inside a double-quoted scalar is not a
  recognized escape and is a YAML parse error, not merely a different regex
  (same trap the media `pdf` field's pattern already documents further
  down).
- **The outbound field is `event_url`, never `url`.** Same DocumentDrop
  shadow as `_media`'s `article_url` (see "Media items are real pages"
  below): a front-matter `url:` key on a collection document is unreachable
  from Liquid, so this collection's field is named `event_url` from the
  start rather than hitting that trap a second time.

**Past events are not auto-hidden — deliberately.** The layout renders every
event in `site.events`, with no date-based filter to drop ones that have
already happened. Filtering on "today" would make the rendered page depend
on the moment it was *built*, not on its content — exactly the
non-determinism the platform's visual-regression lane and this repo's own
test rules (AGENTS.md: "no reliance on wall-clock time") forbid. The owner
removes a finished event from `/admin` herself once it has passed.

**The new `about.yml` field, `lead`, costs above-the-fold space.** Feedback
item 2 split the About card's copy in two: `lead` is a single sentence that
renders *above* the nav pills (in `.intro-lead`), and the rest of `bio[]`
renders *below* them (in `.intro-bio`) — see `_layouts/home.html` and
`assets/css/jodidaniel.css`. `lead` and the nav pills are the only content
above the fold on a laptop-height viewport; every character added to `lead`
pushes the nav pills further down the page, which is exactly what
`measure-fold.js` (see the CSS above-the-fold tuning it drove) exists to
catch before it ships. Keep it to roughly one sentence.

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
the item's optional archived **`pdf`** next to the outbound **`article_url`**,
each with an optional per-item button-label override (`link_label`,
`pdf_label`) — see "Outbound link label + PDF button label" below.

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

### Outbound link label + PDF button label (issues #194, #195)

Before #194, `_layouts/media.html` hardcoded the outbound link's text as
**"Read the article"** for every item, regardless of type — wrong for a
podcast episode, a Supreme Court amicus brief PDF, or a conference talk, and a
literal in the layout besides (never `/admin`-editable). The fix is a per-item
optional override plus a category-derived default, the same shape as
`media_by_category` below:

- **`link_label`** (optional string). When an editor sets it, that exact text
  is the button's label — for the unusual item the category default doesn't
  fit. Left blank, `_layouts/media.html` derives the label from `category`:

  | Category | Default label |
  |---|---|
  | Featured Articles | Read the article |
  | Policy & Advocacy | Read the brief |
  | Podcasts & Interviews | Listen to the episode |
  | Speaking & Panels | About this talk |
  | Press & News | Read the piece |
  | (unrecognized/blank) | Read the article |

  **This map is DUAL-MAINTAINED with the `category` select `options:` in
  `admin/collections.site.yml`**, exactly like `media_by_category` in
  `_layouts/home.html` — adding, renaming, or reordering a category means
  editing the layout's `{%- case page.category -%}` block AND the seam's
  `options:` list, or the new category silently falls back to "Read the
  article" on its own page (the home page's grouped list would also drop it,
  per the existing `media_by_category` rule above).
- **`pdf_label`** (optional string). Same shape, for the PDF download button:
  blank defaults to "Download PDF"; set it to override for an unusual item
  (e.g. an exhibit, a transcript).

`scripts/verify-build-artifacts.rb` asserts the built pages actually carry
more than one distinct outbound-link label (not just the layout source) — the
regression it guards is every page reverting to "Read the article" silently.

**`pdf` must actually be a PDF (issue #195).** Before the fix, the `pdf` field
accepted any file type — upload a `.txt` and the public page rendered a
confident, fully-styled "DOWNLOAD PDF" button that handed the visitor a text
file, with no warning at upload, selection, or publish. Two layers now guard
it:

- **Seam validation.** `admin/collections.site.yml`'s `pdf` field carries
  `pattern: ['\.pdf$', 'Must be a PDF file (.pdf)']`. Decap's `file` widget
  stores the uploaded/selected file's **path string** as the field value, and
  string `pattern:` validation applies to that path — so a non-`.pdf` upload is
  rejected in the editor before it can ever be saved. **Quoting matters**: the
  regex must be **single-quoted** YAML (`'\.pdf$'`) — a double-quoted
  `"\.pdf$"` is a YAML parse error (`\.` is not a recognized C-style escape in
  a double-quoted scalar), so double quotes here don't just behave differently,
  they fail to parse at all. Verify with a real YAML parser, not by eye:
  `ruby -ryaml -e 'p YAML.safe_load(File.read("admin/collections.site.yml", encoding: "utf-8")).find { |c| c["name"] == "media" }["fields"].find { |f| f["name"] == "pdf" }["pattern"]'`
  should print `["\\.pdf$", "Must be a PDF file (.pdf)"]` (Ruby's `inspect` of
  the literal one-backslash string).
- **Layout guard.** `_layouts/media.html` only renders the PDF download button
  when the `pdf` value's last four characters, downcased, equal `.pdf`. This is
  the belt to the seam pattern's braces — a value saved before the pattern
  existed, or a hand-edited front-matter file, still can't render a lying
  "download PDF" button for a non-PDF file. No `pdf` value still renders no
  button, same as before.

**PDF uploads use the site-wide media folder.** The `pdf` field is a plain
Decap `file` widget with no per-field `media_folder`/`public_folder`. The
platform's `config.base.yml` documents `public_folder == "/" + media_folder` as
an invariant enforced by `e2e/cms-config.spec.js` — Decap appends only the
uploaded basename to `public_folder` and does not mirror subdirectories into the
URL, so a per-field override reintroduces the broken-path / "Copy Path" bug.
Uploads land in `assets/images/uploads/` alongside the profile photo.

**The chain is verified by build — and its guard is conditional.** `pdf` is not
shadowed by `DocumentDrop`; that is measured, not inferred from the list above.
Adding `pdf: /assets/images/uploads/<file>.pdf` to a `_media/*.md` and building
renders the "Download PDF" link at exactly that href, and Jekyll copies the file
to `_site/assets/images/uploads/` (it is a plain static asset — no `exclude:`
entry touches it). To re-run that probe:

```sh
cp any.pdf assets/images/uploads/probe.pdf   # bytes are irrelevant to the build
# add `pdf: /assets/images/uploads/probe.pdf` to one _media/*.md, then:
bundle exec jekyll build && ruby scripts/verify-build-artifacts.rb
# revert both when done
```

What that guard does **not** cover by default: the PDF assertions in
`verify-build-artifacts.rb` that key off an entry's own `pdf:` value (`links to
its PDF`, `is published to _site`, and the issue #195 `rendered PDF href ends
in .pdf` check) fire only for entries that actually carry a `pdf:`. No entry
does yet — the widget shipped before any editor used it — so they are vacuous,
and the script prints a `note` saying so rather than letting a green run imply
coverage it lacks. The first real upload arms them. Two OTHER assertions the
same script added for issue #194 are **not** conditional on a `pdf:` — they
scan every built, ungated `/media/<slug>/` page's rendered outbound-link text
and fail if fewer than two distinct labels appear (or if all of them say "Read
the article"), because the catalogue already has entries in more than one
category (`Podcasts & Interviews`, `Policy & Advocacy`, …), so that guard is
armed today, not waiting on a future upload.

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
