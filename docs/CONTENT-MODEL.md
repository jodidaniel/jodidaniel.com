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
| `media`           | `_media/`           | `category`, `title`, `source`, `date_display` (optional), `article_url`, `link_label` (optional), `pdf_archive_file` (optional), `pdf_public` (default `false`), `pdf_label` (optional), `weight` |
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
  (same trap the media `pdf_archive_file` field's pattern already documents further
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

**Media is special**: items carry a `category`, and the five categories live
in **two GROUPS** — the owner's request to separate media appearances/
articles she is quoted in from things she authored/co-authored:

| Group | Categories |
|---|---|
| Authored (her own words, written or formally delivered) | Articles & Commentary; Briefs, Testimony & Reports |
| Appearances & coverage (she spoke, or someone wrote about her) | Talks & Panels; Podcasts & Interviews; Press Coverage |

The old flat five-category list (Featured Articles / Policy & Advocacy /
Podcasts & Interviews / Speaking & Panels / Press & News) mixed the two —
`Featured Articles` held both a blog she writes AND an interview where a
reporter quotes her, which read as if she'd written the interview.

The home layout groups all `site.media` items by `category`, renders a
per-category block with an icon (same as before the split), and now wraps
each GROUP's category blocks in their own `.media-grid` under a group
heading — Group A renders before Group B, so authored work always lists
above appearances/coverage.

**Re-filing an item into the new taxonomy means changing `category` (and
sometimes `weight`), never the filename.** Item files are slugged
`{{weight}}-{{slug}}.md` at creation time, but the slug is not re-derived
when `weight` changes later — **renaming a `_media/*.md` file breaks the
live URL it already publishes at** (see "Media items are real pages" below),
so the split above was done by editing front matter only. The result: a
file's numeric prefix no longer necessarily matches its current `weight` —
this already had precedent before the split
(`1-fda-introduces-….md` has always carried `weight: 0`) and is expected,
not a bug to "fix" by renaming.

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

### `date_display`: month + year, and why it isn't named `date`

The owner's second 2026-08-30 ask: each media item shows the month and year it
ran. The field is **`date_display`**, never `date` — same `DocumentDrop` shadow
that forced `article_url` and `event_url` above: `date` is a `DocumentDrop`
accessor (it lists Jekyll's front-matter `date:` if present, or falls back to
the file's mtime), so a front-matter `date:` key is unreachable from Liquid the
same way a front-matter `url:` key is. `_events` hit this first and named its
field `date_display` for the same reason; `_media` reuses that name rather than
inventing a second one for the identical trap.

`date_display` is a plain optional string (`admin/collections.site.yml`,
`required: false`) — "Month YYYY" (e.g. `"April 2025"`), a bare year, or the
literal `"Ongoing"`. `_layouts/home.html`'s media list and `_layouts/media.html`
render it beside `source`, joined by ` · `, guarded so a blank value adds no
stray separator.

**The date used to live inside `source`** (`"Bloomberg Law, 2018"`); moving it
out is why **`source` must never carry a 4-digit year again** — with
`date_display` rendering alongside it, a leftover year in `source` would show
the date twice. `scripts/verify-build-artifacts.rb` fails on any `_media/*.md`
whose `source` matches a bare `\d{4}`, and separately asserts every item HAS a
`date_display` key (the value may be empty — a real, deliberately-incomplete
content state pending the owner, not a failure) and, where non-empty, that it
matches `Month YYYY` / a bare year / `"Ongoing"`. It also prints a `note`
listing every item still missing a month, so the gap stays visible without
failing the build.

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
  | Articles & Commentary | Read the article |
  | Briefs, Testimony & Reports | Read the document |
  | Talks & Panels | About this talk |
  | Podcasts & Interviews | Listen to the episode |
  | Press Coverage | Read the coverage |
  | (unrecognized/blank) | Read the article |

  `Podcasts & Interviews` now also holds print interviews (moved out of the
  old `Featured Articles`) — "Listen to the episode" is right for the actual
  podcast and wrong for a written interview, which is why those three items
  each carry a per-item `link_label` override ("Read the interview") rather
  than a sixth category.

  **This map is the THIRD leg of a three-way dual-maintenance triangle**,
  alongside the `category` select `options:` in `admin/collections.site.yml`
  and the `media_authored_cats`/`media_coverage_cats` lists in
  `_layouts/home.html` (see "Media is special" above) — adding, renaming, or
  moving a category between groups means editing all three, or the new/moved
  category silently falls back to "Read the article" on its own page, drops
  out of the home page's grouped list, or both.
  `scripts/verify-build-artifacts.rb`'s "Media: authored vs. appearances are
  separated" group cross-checks all three legs and is the only one of the
  three with a build-time guard until now.
- **`pdf_label`** (optional string). Same shape, for the PDF download button:
  blank defaults to "Download PDF"; set it to override for an unusual item
  (e.g. an exhibit, a transcript).

`scripts/verify-build-artifacts.rb` asserts the built pages actually carry
more than one distinct outbound-link label (not just the layout source) — the
regression it guards is every page reverting to "Read the article" silently.

### Archived PDFs — a private archive and an explicit permission gate

Most `_media` items link to something published elsewhere, and an archived PDF
copy is useful (links rot; some pieces are hard to find later). But a PDF of
someone else's article is someone else's copyright, so publishing one is a
decision a person has to make item by item — not a side effect of uploading a
file. Three rules encode that.

**1. The PDF bytes never enter this repo.** `jodidaniel.com` is a PUBLIC GitHub
repository. A committed PDF is world-readable at `raw.githubusercontent.com`
regardless of what the website chooses to render, and git history is immutable —
a later `git rm` fixes the working tree and nothing else. So the archive is a
**private S3 bucket** with public access blocked, and the repo carries only a
*name*:

- **`pdf_archive_file`** (optional string) — the object's file name in the
  archive, e.g. `"1-fda-amicus.pdf"`. It is NOT a site path and NOT a URL.
  Seam-validated with `pattern: ['\.pdf$', …]`.
- **`pdf_public`** (boolean, default `false`) — the permission gate.
- **`pdf_label`** (optional string) — button text; only ever seen when the gate
  is open.

`scripts/media-archive.sh` puts, gets, lists, presigns and audits archive
objects; `scripts/archive-article-pdf.py` renders a provenance-stamped PDF from
an article URL. Neither writes into this repo, and
`verify-build-artifacts.rb` asserts repo-wide that **no `.pdf` is committed** —
so restoring the old upload path fails the build rather than quietly leaking.

> The seam deliberately offers a **string**, not Decap's `file` widget. A `file`
> widget uploads into `media_folder` — which is committed and published — which
> is precisely the leak this design exists to prevent. The verifier asserts the
> old `pdf` field is *absent*, not merely that the new one is present.

**2. Default is withhold, and withhold means absent, not unlinked.** With
`pdf_public` false (or missing), `_layouts/media.html` renders no download
button, and the deploy never copies the object out of the private archive — so
the PDF is not on the website to be found. Hiding a link to a file that is
nonetheless sitting at a guessable URL is not a permission gate; this is why the
verifier's withhold assertion checks that the built page contains no
`/media-pdfs/` href **and not even the file name**, rather than just checking
that no button rendered.

**3. Opening the gate is an editor's explicit act.** Ticking *"Publish this PDF
on the public website"* in `/admin` is the whole opt-in. The hint tells the
editor what the box means: tick it for a US-government work, for something Jodi
wrote and holds the rights to, or where the publisher has cleared it.

The href is **derived, never authored** — `/media-pdfs/<pdf_archive_file>` — so
an editor cannot type a URL that bypasses the gate.

**Suffix guard (issue #195).** Before the original fix, the field accepted any
file type and the page rendered a confident "DOWNLOAD PDF" button that handed
the visitor a text file. Two layers still guard it: the seam `pattern:`
(rejecting a non-`.pdf` value at save time) and the layout, which renders the
button only when the key's last four characters, downcased, equal `.pdf`.
**Quoting matters**: the regex must be **single-quoted** YAML (`'\.pdf$'`) — a
double-quoted `"\.pdf$"` is a YAML parse *error*, not merely a different regex.
Verify with a real parser, never by eye:

```sh
ruby -ryaml -e 'p YAML.safe_load(File.read("admin/collections.site.yml", encoding: "utf-8")).find { |c| c["name"] == "media" }["fields"].find { |f| f["name"] == "pdf_archive_file" }["pattern"]'
# => ["\\.pdf$", "Must be a PDF file name (.pdf)"]
```

**What the build verifies, and what it cannot.** `verify-build-artifacts.rb`
splits the PDF assertions two ways and reports which half ran, because "All
assertions passed" over zero of both would be a green light wired to nothing:

| entry state | assertion |
|---|---|
| key, `pdf_public: false` | page carries no `/media-pdfs/` href and no file name |
| key, `pdf_public: true`  | page links `/media-pdfs/<key>`, href ends `.pdf`, **and the file exists in `_site`** |
| no key | nothing (a legitimate content state) |

That last publish-side row is why a ticked box still **fails** the build: the
step that copies an opted-in object out of the private archive is platform-side
(`cms-platform`) and is not wired into this repo's deploy callers yet. That is
deliberate — better a loud red than a "Download PDF" button that 404s. Both
halves were proven able to fail: flipping one entry to `pdf_public: true` fails
the `_site` existence check, and removing the `pdf_public` test from the layout
fails all eight withhold assertions.

**The bucket exists and the deploy is wired.**
`jodidaniel-com-media-archive` is live and verified private (public access
blocked on all four axes, no bucket policy, versioning on, AES256), and the
GitHub Actions role holds its own read-only statement — `s3:GetObject` +
`s3:ListBucket`, so a deploy can copy a capture out but can never overwrite or
delete the only copy. Step 5 of the platform's `docs/MEDIA-ARCHIVE.md` is now
done here: `media_archive_bucket` is set on **both** deploy callers, and
`platform_ref` on the production one.

That pair is not decoration on the production caller, and the platform enforces
it rather than trusting a comment. The reusable declares `platform_ref` with
`default: main` — not a pin — and the `media_archive_bucket != ''` steps check
the platform out at that ref to run `publish-opted-in-pdfs.sh`. Set the bucket
without it and the site would publish PDFs to its live domain from an
**unpinned** `main` checkout. `check-platform-pin-consistency.js` fails the
build on exactly that shape (`workflow-content: media_archive_bucket without
platform_ref`), so the mistake is caught rather than deployed.

**This was blocked for one release, and the history is worth keeping.** At
platform v0.1.93 the documented opt-in was unshippable by *any* consumer: step 5
told sites to add the keys, `examples/site` shipped them commented out, and the
checker compared a caller's `with:` key set against those examples as an exact
sorted-set match — and comments drop out in the YAML parse. So following the
docs necessarily produced `workflow-content: DRIFT` on the required
`pin-consistency` check. Verified on PR #224: adding both keys failed the guard,
reverting them passed, and this repo backed the wiring out in commit `07e5c4b`.
The wiring itself was never the problem — on that same run the preview deploy
executed `publish-opted-in-pdfs.sh` against the real bucket and logged
`no media entry has 'pdf_public: true' - nothing published from the archive`.
cms-platform#360 fixed it by exempting the two opt-in keys from the key-set
compare (and adding the pairing assertion above); it shipped in **v0.1.95**,
which is the ref this repo now pins.

**What is still outstanding is the bytes.** All 8 `_media` entries naming a
`pdf_archive_file` are `pdf_public: false` on `main`, so a production deploy
finds nothing opted in and exits 0. But the archive objects are not uploaded —
`bash scripts/media-archive.sh audit` lists all 8 as missing. That matters the
moment a box is ticked: with the deploy wired, an entry whose `pdf_public` is
true and whose object is absent now **fails the deploy loudly** (`exit 1`)
rather than shipping a "Download PDF" button that 404s. Upload the object first,
then tick the box.

**Adding an archived PDF, end to end.**

```sh
# 1. render it (or obtain the publisher's own PDF)
python3 scripts/archive-article-pdf.py /tmp/out worklist.json
# 2. check it is not a paywall stub — under ~800 chars of body is not an archive
# 3. upload to the PRIVATE archive (never into this repo)
bash scripts/media-archive.sh put /tmp/out/<slug>.pdf
# 4. in /admin, set "Archived PDF" to <slug>.pdf; leave the publish box UNTICKED
#    unless we may lawfully republish it
```

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
