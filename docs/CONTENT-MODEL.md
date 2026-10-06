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
| `_data/settings.yml` | `site_live` GATE, `coming_soon`, `seo` (site name, launch title, Google description), `footer`, `back_to_top_label`, `skip_link_label`, `section_headings`, `share` (search-engine-only facts) | **Site Settings** (`site_settings`) |
| `_data/not_found.yml` | `heading`, `message`, `home_link_label`, `skip_link_label` — the 404 page (`404.html` → `_layouts/not-found.html`) | **Site Settings** → "Page-Not-Found Page" (`site_settings` file `not_found`) |

The layout reads these as `site.data.header` / `.about` / `.contact` /
`.settings`. The 404 page reads `site.data.not_found`. It is a site-owned layout
(the theme's dark `default` layout and its "RSS" link are gone from it); it
renders no bio content, so it is safe while `site_live` is false, and
cms-platform's `e2e/not-found.spec.js` skips for it (that spec runs only when the
404 uses the theme layout), so `scripts/verify-build-artifacts.rb` carries the
header, footer, `h1`-in-`main`, skip-link and home-link checks instead. The icon set (`assets/favicon.svg`
plus `favicon.ico`, `favicon-32x32.png`, `apple-touch-icon.png`) is rendered by
`scripts/render-icons.mjs`; `_includes/favicon.html` shadows the theme's and
links all of it (and still honors `cms.favicon_url`, verbatim, as the theme's does; `scripts/test-favicon-include.rb` covers that). `assets/images/uploads/e2e-preview-media-probe.png` looks like
a stray test image but is a sentinel cms-platform's `preview-media` gate and
pin-consistency check require: do not delete it.

### Share titles, `Person` data and media-page schema (audit #4/#5)

The open home page's `{% seo %}` output is led by her name in the share titles,
and it carries one `Person` entity; media item pages describe themselves
honestly. **No link-preview image is set** (that work is separate, and whether
her headshot belongs on a preview is an open decision).

- **Open**: `_includes/home-seo.html` calls `{% seo %}` with the share titles led
  by her name (the tab `<title>` is unchanged) and adds one `Person` JSON-LD
  built only from repo content: current role and firm (first Experience item
  whose `period` contains "present", any case; none means no job title), schools (Education), areas (Expertise),
  `sameAs` from Contact links plus `settings.share.profile_links`, and
  `alternateName` from `settings.share.alternate_names`.
- **Media item pages** write their own head (not `{% seo %}`): a `WebPage`
  that is part of the site, with a per-item description. The tag would type
  every collection document as her `BlogPosting` dated at build time.

`scripts/verify-build-artifacts.rb` ("share titles + structured data") asserts all
of it, deriving the expected Person from the source files
(`scripts/person_rules.rb`) rather than hardcoding facts, so ordinary `/admin`
edits do not trip it; `scripts/test-person-rules.rb` builds the edited cases.

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
the two apart fails the build instead of shipping a dead pill. On the
committed build that check is vacuous while `site_live: false` (the gate hides
every section, so there is nothing built to check anchors against), and it
prints a `note` saying so. The verifier's second, open-gate pass (issue #306,
see "What the build verifies" further down) runs it for real against a
disposable build with the gate forced open, where a skip is a failure.

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
  `\A\d{4}-\d{2}-\d{2}\z` for exactly this reason. The admin seam uses the
  equivalent `pattern: ['^[0-9]{4}-[0-9]{2}-[0-9]{2}$', ...]`. Its
  backslash-free spelling survives the whole-fragment YAML round-trip that a
  platform field-library `$ref` activates while keeping the same date shape.
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
to a built page, or if the rendered admin config loses the shared PDF fields.
The same trap
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
  Must end in a lowercase `.pdf` (see "Suffix guard" below).
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
on jodidaniel.com"* in `/admin` is the whole opt-in. The shared platform hint
keeps the rule site-neutral: publish only when the owner has permission, owns
the rights, the work is in the public domain, or the publisher has cleared it.
The hostname is filled from the routed admin host at runtime.

The href is **derived, never authored** — `/media-pdfs/<pdf_archive_file>` — so
an editor cannot type a URL that bypasses the gate.

**Suffix guard (issues #195, #305).** Before the original fix, the field
accepted any file type and the page rendered a confident "DOWNLOAD PDF" button
that handed the visitor a text file.

**The suffix rule: the name ends in a lowercase `.pdf`, compared
case-sensitively.** `report.pdf` qualifies; `report.PDF`, `report.Pdf`,
`report` and `report.pdf.txt` do not. There are two rules in play, a looser one
and a stricter one, and each link in the chain enforces its own:

- the shared field-library `pattern: ['[.]pdf$', ...]` enforces **the suffix
  only**, at save time in `/admin` (the character class is deliberately
  equivalent to `\.` without carrying a backslash through the `$ref` YAML
  render). It would accept `my file.pdf` or `a/b.pdf`;
- `_layouts/media.html` enforces **the suffix only**: it renders the button only
  when the name's last four characters equal `.pdf` exactly. It used to downcase
  them first, so `report.PDF` got a button for a file the deploy would never
  publish;
- the platform's `publish-opted-in-pdfs.sh` enforces **the full rule**, but only
  at deploy time and only for an entry whose `pdf_public` is true: the name must
  match `^[A-Za-z0-9._-]+\.pdf$` (letters, numbers, dot, dash and underscore;
  no spaces, no slashes) and contain no `..`, or the deploy fails;
- `verify-build-artifacts.rb` enforces **the full rule before deploy**: every
  real entry with `pdf_public: true` must have a name the deploy would accept,
  and a name it would refuse fails the required check with a message naming the
  entry, the rule and what to do. It also holds every committed entry's name to
  the field's own suffix pattern (catching a hand edit Decap never validated),
  and checks the built pages against all five example names above.

The rule is about the suffix only. The rest of the name keeps its casing: the
href is `/media-pdfs/<pdf_archive_file>` verbatim, matching the object's name in
the archive. If an archived object's name ends in `.PDF`, rename the object to
end in `.pdf` rather than changing the rule.

**What the build verifies, and what it cannot.** `verify-build-artifacts.rb`
splits the PDF assertions by entry state and reports which ran, because "All
assertions passed" over zero of them would be a green light wired to nothing:

| entry state | assertion |
|---|---|
| key, `pdf_public: false` | page carries no `/media-pdfs/` href and no file name |
| key the deploy accepts, `pdf_public: true` | page links `/media-pdfs/<key>`, href ends `.pdf`, **and the file exists in `_site`** (a stand-in the verifier stages; see below) |
| key the deploy would refuse (space, slash, `..`, other characters), `pdf_public: true` | the check fails with a plain-language message naming the entry and the rule |
| key not ending in lowercase `.pdf`, `pdf_public: true` | page shows no PDF button and no `/media-pdfs/` href |
| no key | nothing (a legitimate content state) |

**It runs them twice (issue #306).** While `site_live` is false every media page
is a coming-soon shell, so on the committed build none of those rows has a page
to read, and neither do the nav, Events, Media-grouping and above-the-fold
groups. So after checking the committed `_site`, the verifier copies the source
into a temporary directory outside the repo (without `.git`), forces
`site_live: true` in that copy only, adds six synthetic `_media` entries (one
withheld, one published, and `.PDF`, `.Pdf`, no suffix and `.pdf.txt` names,
all ticked), builds it, and runs every assertion again. On that pass a group
the gate would hide is a failure, and each PDF row above must run at least
once. The temporary directory is deleted when the run ends, so that build is
never deployed, and the verifier asserts the committed `_data/settings.yml` is
byte-for-byte unchanged afterwards. Both passes print how many assertions they
executed.

**Whether the object is in the archive is the deploy's check, not the PR's.**
CI never reads the private archive; only the deploy's
`publish-opted-in-pdfs.sh` does, and it exits non-zero, loudly, when an opted-in
object is missing. So on the open-gate pass the verifier writes a stand-in file,
where that script would put it, for **every** `pdf_public: true` entry in the
copy's `_media`, real ones as well as the synthetic fixtures, whenever the
deploy would accept the name. Ticking "Publish this PDF" on a real entry with a
valid name therefore keeps `site-verify` green and the CMS pull request
mergeable; if the object was never uploaded, the deploy is what stops it, by
failing instead of shipping a "Download PDF" button that 404s. (An earlier
version staged a stand-in only for the fixtures, which made that tick a dead end:
the PR could never merge, because CI cannot see the file the deploy would copy.)
What CI **can** check, and does, is the name: see the full rule above. Upload
the object first, then tick the box.

These rows were proven able to fail: a real entry ticked with a name containing
a space, a slash, `..` or an uppercase `.PDF` turns the name check red, and with
a valid name it stays green; making the open-gate flip a no-op fails the pass
closed; removing the `pdf_public` test from the layout fails all eight withhold
assertions; and putting the layout's `downcase` back fails the `.PDF` and `.Pdf`
rows.

**The temporary copy holds tracked files only.** It is built from exactly the
files `git ls-files` reports, never from "everything except", so the gitignored
local content a working checkout carries (`infrastructure/site-params.env`, which
holds real OAuth credentials, `.cms-platform`, `.jodidaniel-real-content`,
`e2e/node_modules`) never reaches `/tmp`. Without git metadata (a tarball
checkout) it walks the tree instead and refuses `infrastructure/`, `*.env` and
the same local-only names. The verifier asserts the copy holds nothing outside
that list, and removes the directory when the run ends. A run killed
mid-build (a `SIGKILL`, or even a `SIGTERM` while Jekyll is still writing its
cache) can leave a `/tmp/verify-open-gate-*` directory behind; because of the
allowlist it holds only tracked source, never credentials. A file you have not
yet `git add`ed is not in the copy.

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
so any ref from that release onward carries it.

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

`/admin` shows **10 per-section editors** — the 6 folder collections + the 4
file collections above — and **nothing else**. The generic platform
collections (posts / tags / projects / pages / e2e) are hidden by
`cms.base_collections: []` in `_config.yml` (an empty keep-list hides them all;
honored by `cms-platform-theme` >= v0.1.7). This single-page bio has no blog.

The admin UI itself is **delivered by the gem** (`cms-platform-theme`), not
vendored here. The only admin file this repo owns is the **site seam**
`admin/collections.site.yml`: a YAML fragment of Decap collection definitions
that references the platform's reusable `archived_pdf_fields` group. The
platform's render hook resolves that `$ref`, then splices the result into the
base config at the
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
