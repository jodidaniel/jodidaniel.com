# Exploratory UI testing — protocol, personas, and local runbook

Human-eye acceptance testing for this site: a set of persona-driven
exploratory missions run by agents (or people) against a **local instance**,
using only inputs a human has — clicks, taps, typing, scrolling — and judging
only what is visible on screen. First used against PR #176 (the go-live
build); written to be reusable for any future content or platform change.

Three rules make the results trustworthy, and they are non-negotiable:

1. **Human inputs only** — no DOM event synthesis, no element-property
   setting, no `page.evaluate`, no request mocking. (`locator.fill()` counts
   as property-setting; type instead.)
2. **Blind to the invisible** — findings come from rendered, visible state
   (screenshots actually looked at), never from source, configs, or hidden
   DOM.
3. **Emergent findings are first-class** — every report carries an
   "Emergent observations" section for things noticed OFF the scripted path;
   testers are told wandering eyes are the point.

## Standing up a local instance

From a clean checkout of the ref under test:

```sh
bundle config set --local path vendor/bundle && bundle install
LANG=C.UTF-8 LC_ALL=C.UTF-8 bundle exec jekyll serve --port 4000  # public site
npx decap-server                                                  # admin backend, port 8081
# admin: http://127.0.0.1:4000/admin/index-local.html
```

Gotchas measured while setting this up (2026-08-29, platform v0.1.90),
**both since fixed upstream** — re-measured on v0.1.91-rc.1:

- ~~Set a UTF-8 locale~~ — **no longer required.** Under a POSIX/C locale the
  gem's Decap render hook used to crash with `invalid byte sequence in
  US-ASCII` (cms-platform#213 fixed the script render path and never covered
  the gem-hook path). cms-platform#327 pinned the hook's reads to UTF-8, and
  this repo's `scripts/verify-build-artifacts.rb` was fixed the same way.
  Re-measured with `LANG`/`LC_ALL` unset: build exits 0, no encoding error.
  Testing a ref older than platform v0.1.91 still wants `LC_ALL=C.UTF-8`.
- ~~Patch the gem to get collections in the local admin~~ — **no longer
  required.** `/admin/index-local.html` used to render with ZERO collections
  on this site until the gem's `config-local.base.yml` gained the
  `# __SITE_COLLECTIONS__` splice marker; cms-platform#327 added it. Measured
  on v0.1.91-rc.1: the rendered `config-local.yml` is 220 lines and declares
  all 9 collections (was 38 lines ending in an empty `collections:`).
  **Do not hand-patch `vendor/bundle/` for this any more** — if collections
  are missing, check the pinned platform_ref before reaching for a patch.
- The local backend is decap-server in **simple mode**: no editorial
  workflow (Draft/Review/Ready) — a Save applies immediately and the watcher
  rebuilds the site in ~2–10s. Prod behavior differs there; everything else
  (editors, fields, validation, media library) is the production admin UI.
- **Sandboxed/egress-restricted environments** (Claude Code cloud): the
  admin shell loads Decap from unpkg.com and the pages load Google Fonts —
  both may be blocked. Mirror them from npm (`npm pack decap-cms@<pinned>`,
  `@fontsource/raleway`, `@fontsource/source-sans-pro`), drop
  `decap-cms.js` into the vendored gem's `theme/admin/` (the render hook
  copies it into `_site/admin/`), point the shell's `<script src>` at it,
  and serve the fonts from a local stylesheet. Test-instance-only edits —
  never commit them.
- To test the **coming-soon state**, flip `site_live: false` in
  `_data/settings.yml` of the test copy (or, better, have the owner persona
  flip it through /admin — that rehearses the real go-live lever).
- **Keep every harness artifact OUT of the Jekyll watch tree.** Server logs,
  tester screenshots, scripts, and reports written inside the instance
  directory trigger watcher rebuilds — a server logging its own rebuilds into
  an in-tree `serve.log` is a self-sustaining regen loop that took two
  instances down (OOM-shaped death mid-regeneration). Point stdout/stderr
  outside the tree AND run `jekyll serve` with a second config
  (`--config _config.yml,<override>.yml`) whose `exclude:` = the site's
  original list + `probe`, `fixtures`, `REPORT.md`, `serve.log`, `decap.log`.
- **Process hygiene with concurrent testers**: browsers share one Chromium
  binary, so a tester must never `pkill` by binary path (one did, and may
  have killed siblings' browsers); kill only PIDs your own scripts spawned.
  Budget memory — six Jekyll watchers + several Chromium sessions + an npm
  `ci` fit in ~16 GB with little slack, and contention shows up as fake
  "site is slow/blank" symptoms in tester reports; stagger anything heavy.
- Agent harnesses may refuse to Write report-shaped `.md` files; a Bash
  heredoc (`cat > REPORT.md <<'EOF' ...`) is the accepted fallback.
- Run testers on **isolated copies** (one per tester, `.git` excluded so a
  scratch tree has no push reach; separate ports; a second decap-server
  needs `PORT=<n>` plus `local_backend: {url: "http://localhost:<n>/api/v1"}`
  in the copy's gem config).

## Testing the DEPLOYED site from a sandboxed session (issue #200)

Issue #200 moves the method onto the deployed site with the real GitHub
backend. Two boundaries decide what a session can do there, and both were
measured on 2026-09-02 (platform v0.1.101, prod and `preview-pr220`):

- **The credential boundary is the operator's, full stop.** The real `/admin`
  is behind GitHub OAuth; a session does the unauthenticated subset and reports
  BLOCKED for the rest until a logged-in browser or a scoped credential is
  handed over (#200, hard boundary 1). Nothing below changes that.
- **Chromium in a Claude Code cloud session cannot reach the deployed site at
  all.** Playwright's Chromium ignores `HTTPS_PROXY`, so the first symptom is
  `ERR_CONNECTION_RESET` on every URL; pass the proxy explicitly
  (`chromium.launch({ proxy: { server: process.env.HTTPS_PROXY } })`) and the
  CONNECT succeeds, then the egress gateway closes the tunnel 6 s after the
  TLS ClientHello with nothing back. It is not the handshake size: 1802 B with
  Chromium's post-quantum key share, 534 B with it off (enterprise policy
  `PostQuantumKeyAgreementEnabled: false`), 522 B with HTTP/2 and QUIC
  disabled — same outcome each time, while `curl` fetches the same URLs
  without complaint (the proxy's `/__agentproxy/status` logs each attempt as
  `ws_closed_mid_exchange`). So the protocol's "look with your eyes" rule
  cannot be met from the sandbox against a DEPLOYED target; the screenshot
  half needs a browser outside the proxy — the operator's own, or a CI
  runner — and a sandbox session should say so rather than spend an hour on
  proxy flags.

What a sandbox session CAN establish, unauthenticated, with `curl` plus a
text extractor: HTTP status, tab title, the visible copy of the public pages,
the 404 and `/preview/` pages, link labels against their destinations, and
whether test content is really gone after cleanup. What it cannot judge:
layout, contrast, spacing, and anything Decap renders — the `/admin` login
screen included, because the shell is static and Decap mounts client-side
from unpkg.

Two checks before judging anything on a deployed `/admin`:

- **Confirm the CDN is serving the pinned platform.** `deploy-production`
  fires its CloudFront invalidation without waiting for it, so the edge can
  serve the previous admin for minutes after a green deploy (cms-platform
  `AGENTS.md`, "A validation dispatch tests the code that is REACHABLE").
  Curl a served asset and grep for a symbol the pinned release introduced,
  e.g. `curl -s https://<host>/admin/publish-progress.js | grep -c
  'no-cache'` is non-zero from v0.1.101 on.
- **Confirm the preview target is current with `main`.** A preview belongs to
  a PR, and only that PR's merges from `main` move it:
  `git fetch origin <pr-branch> && git merge-base --is-ancestor origin/main
  FETCH_HEAD` says whether the preview carries everything on `main`.

## Report contract and missions

The protocol below is handed to every tester verbatim; the five missions
cover a first-time desktop visitor, a phone + keyboard-only visitor, the
pre-launch (gated) state, and two non-technical-owner /admin sessions.

---

<!-- ══════════════════ THE PROTOCOL (handed to every tester verbatim) ══════════════════ -->

# Exploratory UI testing protocol — jodidaniel.com (PR #176 golive build)

You are one of several independent testers exploring a locally-running copy of
jodidaniel.com exactly as a human would. You have a persona and a mission (in
your prompt). This file is the shared contract. Follow it exactly.

## What you are testing

A single-page professional bio site for Jodi Daniel, a digital health law &
policy leader, plus (owner personas only) its /admin content editor. The build
under test is the "go-live" pull request. Your instance is yours alone — no one
else is using it, and nothing you do in it can reach the real site.

## Hard interaction rules (the whole point of this exercise)

1. **Human inputs only.** Interact through Playwright exclusively with:
   - `locator.click()` / `dblclick()` / `hover()`, `mouse.*`, `mouse.wheel`
   - `keyboard.type()`, `keyboard.press()`, `locator.pressSequentially()`
   - `page.goto()` ONLY for entry URLs given in your mission, or when your
     mission explicitly says "type a URL like a person would"
   - For file uploads: click the real upload control, catch the
     `filechooser` event, and hand it a fixture file. (That is the stand-in
     for the OS file dialog, which is not part of the page.)
2. **Never**: `page.evaluate()` / `evaluateHandle()` to read or change the
   page, `dispatchEvent`, setting element properties or values directly,
   `locator.fill()` (type instead — `pressSequentially`; clear a field with
   click + `Control+a` + `Delete`), `page.route()` or any request mocking,
   touching localStorage/sessionStorage, adding scripts or styles.
3. **Be blind to the invisible.** Findings must come from what a sighted
   person sees in the rendered page: your screenshots, visible text, visible
   state. Allowed: reading the destination URL of a VISIBLE link (that's the
   browser status bar on hover) and noticing that a new tab opened. Forbidden
   as a basis for findings: hidden DOM, page source, config/data/build files,
   server logs, code. Do not open any file of the site's source tree.
   Exception: if a page is visibly broken/blank, you may quote a console or
   network error as supporting evidence in the "Technical appendix" of your
   report — never as a finding on its own.
4. **Look with your eyes.** After every screenshot, actually open it with the
   Read tool and study it before moving on. Judgments about layout, contrast,
   alignment, typography, spacing must come from looking at the image, not
   from element queries. Take a screenshot at every meaningful step and at
   every viewport you use. Save all screenshots under `probe/shots/` in your
   instance directory with descriptive names.
5. **External links: do not click through.** The sandbox blocks most external
   network access; an external page failing to load is an environment
   artifact, never a site bug, and must not be reported as one. Instead:
   note the link's visible label and its destination URL, judge whether the
   destination plausibly matches the label, and (where your mission says so)
   verify that activating it opens a NEW tab rather than replacing the site.
   Close such tabs immediately.

## Environment facts (so you don't report the harness as a bug)

- The site runs at the localhost URL in your mission. It is a static Jekyll
  site with a file watcher: after content is saved through /admin, the site
  rebuilds in ~2–10 seconds. Reload the public page after a save; if a saved
  change is still absent after ~20s and two reloads, THAT is reportable.
- Fonts and the admin's JavaScript are served locally (byte-identical
  mirrors) because the sandbox blocks their CDNs. If typography looks like a
  plain default font, mention it in the Technical appendix, not as a finding.
- OWNER personas: the local admin backend is "simple mode". The real
  production admin has an extra Draft → Review → Ready workflow; locally,
  clicking Publish/Save applies the change directly. Do NOT report the
  absence of workflow states, and treat wording around "Publish" with that
  grain of salt. Everything else (editors, fields, validation, media library,
  navigation) is the real UI.
- The admin's "reviews" dashboards and anything that talks to GitHub are out
  of scope locally.
- A tiny camera icon / avatar in the admin top bar relates to the backend
  user; ignore auth-related oddities (local mode has no real login).

## Safety rules

- Work ONLY inside your instance directory and your `probe/` subdirectory.
- Never touch `/home/user/jodidaniel.com` or any other repo checkout.
- Do not run `git`. Do not start, stop, or restart servers. Do not edit the
  site's files directly — owner personas change content ONLY through the
  admin UI in the browser; visitor personas change nothing at all.
- Use no credentials of any kind; there are none to use and none are needed.
- No network access beyond your localhost URLs (whatever the browser fetches
  by itself is fine and may fail harmlessly).

## Playwright harness

- Use node with `NODE_PATH=/opt/node22/lib/node_modules` and
  `require('playwright')`; launch chromium with
  `executablePath: '/opt/pw-browsers/chromium'`.
- Do NOT run `playwright install`.
- Set the viewport your mission specifies. `deviceScaleFactor: 2` is allowed
  for crisper screenshots.
- Keep one browser context per journey so history/back/forward behave like a
  real session. Listen for `context.on('page', ...)` to notice new tabs.
- Write small scripts per journey in `probe/` (e.g. `probe/01-first-visit.js`)
  so a failed step doesn't lose earlier evidence.

## Report contract (mandatory)

Write `REPORT.md` at the ROOT of your instance directory. Structure:

1. `## Summary` — 3–6 sentences: overall impression in persona, plus the
   single most important thing you found.
2. `## Findings` — numbered F1, F2, …; each with:
   - **Severity**: `blocker` / `major` / `minor` / `nit` / `question`
   - **Where**: page/URL + viewport
   - **What I did** (exact human steps), **What I saw** (reference screenshot
     filenames), **What I expected as a human**
3. `## Emergent observations` — REQUIRED, even if empty: things you noticed
   OUTSIDE your scripted path — odd wording, a typo, a slow or janky moment,
   an inconsistency, something confusing, something delightful. Wandering
   eyes are the point; report what caught them.
4. `## Environment artifacts noticed` — anything that smelled like the
   sandbox rather than the site.
5. `## Technical appendix` — console/network notes (optional, short).
6. `## Coverage` — your mission's checklist as a table: item → DONE /
   PARTIAL / SKIPPED (+why). End with the line
   `Coverage: N of M checklist items DONE` with real numbers.

Severity calibration: `blocker` = a normal person cannot complete a core
thing or the site is visibly broken; `major` = works but would embarrass the
owner or confuse most users; `minor` = noticeable rough edge; `nit` = polish;
`question` = behavior that may be intentional but deserves a human decision.

Be concrete and honest. "I could not tell whether X" is a valid observation.
Do not pad; do not soften; do not invent findings to seem thorough. If a step
was impossible, mark it SKIPPED with the reason — never fake it.

<!-- ══════════════════ MISSION V1 ══════════════════ -->

# Mission V1 — First-time visitor, desktop, live site

**Persona**: General counsel at a health-tech company. You heard Jodi Daniel
speak on a panel, someone mentioned she has a website, and you typed
jodidaniel.com into your laptop browser. You are busy, skeptical, and used to
polished professional sites (big-law bio pages, LinkedIn). You are deciding in
the first 30 seconds whether this person is credible, and in the next five
minutes whether to contact her.

**Instance**: site at `http://127.0.0.1:4001/` — this is your ONLY entry URL
(plus URLs you deliberately "type" per the checklist). Viewport 1440×900
(scroll like a person: wheel or PageDown, not instant full-page jumps —
full-page screenshots are allowed for the record, but judge above-the-fold
first). Also do one pass at 1920×1080 and one at 1280×800 for layout sanity.

## Checklist (12 items)

1. **First impression**: load the home page; screenshot before scrolling.
   What do you understand about this person in 5 seconds? Does anything look
   off (alignment, contrast, cramped or empty areas, image quality)? Does the
   page feel finished? Note the browser tab title — is it what you'd expect
   on a professional's live site?
2. **Read the About area**: photo, heading, bio paragraphs. Judge as a human:
   typos, awkward phrasing, claims that contradict each other, dates or
   numbers that don't add up ("over 30 years…including 15 years…" — do the
   claims cohere?). Does the photo look right (not stretched/pixelated)?
3. **In-page navigation**: click EACH of the nav links under the bio
   (Expertise, Experience, Accomplishments, Media, Education, Contact), one
   at a time. After each click: did the page land where a person would
   expect (the section heading visible near the top, not cut off or buried)?
   Is there any way to get back to the top without scrolling manually? Would
   you expect a persistent menu once you've scrolled deep?
4. **Expertise & Experience sections**: read them. Hover over cards and
   timeline entries — any hover affordances that promise interactivity but do
   nothing? Any inconsistent punctuation/capitalization across cards? Does
   the timeline read in a sensible order?
5. **Accomplishments**: read all bullets. Same editorial eye.
6. **Media section — the big one.** For EACH of the five category groups,
   click at least one item (click the title like a person). For each:
   a. You land on that item's own page. Does it match what you clicked
      (title, source)? Is the page worth the stop, or does it feel like a
      pointless interstitial between you and the article?
   b. Click the action button on the item page. Does it open the article in
      a NEW tab (do not wait for the external page to load; note the
      destination URL and close it)? Does the button's LABEL make sense for
      the kind of item (an article vs a podcast episode vs a court brief vs
      a panel talk)?
   c. Use the "Back" link on the item page. Where does it put you? Then also
      try the BROWSER back button from an item page. Do both behave the way
      you'd expect?
7. **Media destinations sanity**: for ~6 items across categories, compare the
   visible title/source against the destination URL (hover-equivalent). Flag
   any that look mismatched (e.g. a talk pointing at a generic profile page
   rather than anything about the talk).
8. **Education & Contact**: read; then activate both contact buttons (new
   tab? destination plausible for the label?). As a would-be client: is
   there any way to actually CONTACT her from this page (email, phone,
   form)? Is what's offered enough?
9. **Footer**: read it. Anything odd?
10. **URL curiosity**: like a person would, edit the address bar: try
    `http://127.0.0.1:4001/media/` (trimming an item URL back to the
    folder), and `http://127.0.0.1:4001/anything-wrong/`. Judge what you get
    on each — as a visitor, does the site handle your mistake gracefully?
    Does the error page feel like the same site? Use its link(s) to get back.
11. **Text selection & copy**: select the bio text and a media item title as
    if copying into an email — anything weird (unselectable, odd characters)?
12. **Widths**: repeat a quick visual pass at 1920×1080 and 1280×800:
    screenshot home top + media section + contact; look for stretched lines,
    cramped columns, misaligned cards.

Then: **free exploration** (at least 10 minutes' worth) — follow your own
curiosity anywhere on the public site; report what you notice under Emergent
observations.

<!-- ══════════════════ MISSION V2 ══════════════════ -->

# Mission V2 — Visitor on phone + keyboard-only visitor, live site

**Persona A (primary)**: A conference attendee who just met Jodi and opens
jodidaniel.com on their iPhone in a taxi. One thumb, bright daylight, in a
hurry.

**Persona B (secondary)**: A keyboard-only user (motor impairment, or just a
power user) on a laptop — no mouse at all.

**Instance**: site at `http://127.0.0.1:4002/` — your ONLY entry URL.

## Part A — Phone (viewport 390×844, `isMobile: true`, `hasTouch: true`; use `tap()` where natural) — 8 items

1. **First screen**: screenshot before scrolling. Is the name/tagline
   legible? Anything cut off? Is text comfortably sized or squint-small?
2. **Scroll the whole page** in realistic increments, screenshotting each
   section as it comes. LOOK at every screenshot: contrast problems (pale
   text on the blue gradient), cards touching screen edges, awkward wraps,
   giant gaps. Pay particular attention to whether every section's text
   sits on a readable background.
3. **Horizontal integrity**: at several scroll positions, try to swipe/scroll
   sideways (mouse.wheel deltaX or touch drag). Does the page wiggle
   horizontally or stay locked? Any content visibly clipped at the right
   edge anywhere?
4. **In-page nav links**: tap 3 of them. Do they land well on a phone (is
   the section heading visible after the jump, or does something overlap
   it)? Are the nav links big enough to tap with a thumb without hitting
   the neighbor (judge from the screenshot AND from whether your tap on the
   edge of one activates the right target)?
5. **Media on mobile**: tap into 2 items from different categories; judge
   the item page at phone width (title wrap, button size and centering,
   back-link reachability). Action button: does it visibly react to tap?
   New tab? Then get back to the media LIST both ways (page's back link;
   browser back).
6. **Contact buttons**: reachable and tappable? Judge size/spacing.
7. **Landscape**: rotate (844×390) and skim the top + one media page —
   anything broken?
8. **Tablet**: 768×1024 pass over the whole page (screenshot per section);
   note anything that looks worse than phone or desktop (this is the width
   where grids change shape).

## Part B — Keyboard-only (viewport 1440×900, NO mouse for interaction) — 4 items

9. From a fresh page load, press Tab repeatedly all the way through the
   page. Is there ALWAYS a visible focus indicator telling you where you
   are? Screenshot the focused state at several stops (nav links, a media
   item, contact buttons). If focus ever disappears (you're tabbing blind),
   that's a finding: say between which two visible stops it vanished.
10. Is the focus order sane (roughly top-to-bottom, left-to-right; nav →
    sections → contact → footer)?
11. Activate an in-page nav link with Enter; then Tab onward — does focus
    continue from the section you jumped to, or from where you were (i.e.
    do you have to tab through the whole page again to reach the section's
    links)? Judge as the keyboard user.
12. Reach a media item with the keyboard, Enter into it, and use the item
    page's back link by keyboard. Any traps (something you can see but
    can't reach, or reach but can't activate)?

Then: **free exploration** on either device; Emergent observations required.

<!-- ══════════════════ MISSION V3 ══════════════════ -->

# Mission V3 — Visitor while the site is still gated ("coming soon" state)

**Persona**: Two hats. (1) A colleague who heard the site exists and checks
it before it launches. (2) A journalist who was emailed a link to one of the
media pages ahead of launch.

**Instance**: site at `http://127.0.0.1:4003/` — built with the launch gate
CLOSED (this is what the public sees before go-live). Your ONLY entry URL,
plus the specific URLs in the checklist.

## Checklist (7 items)

1. **Home, desktop 1440×900**: screenshot. What exactly does a visitor see
   pre-launch? Is it dignified and intentional-looking, or broken-looking?
   Tab title? Anything visible that should NOT be public yet (any bio
   content, any hint of the full site)?
2. **Scroll + interact**: is there anything below the fold? Anything
   clickable at all? Does the page invite you to come back or contact
   anyone? (Judge whether that's a problem or fine for a coming-soon page.)
3. **Home, phone 390×844**: same judgments.
4. **Deep link while gated**: "type" `http://127.0.0.1:4003/media/1-fda-amicus/`
   (the journalist's emailed link, hypothetically). What renders? As the
   journalist: do you understand what happened, or does it feel broken (an
   empty page with just a name)? Is any article content visible? Tab title?
5. **Wrong URL**: `http://127.0.0.1:4003/does-not-exist/` — same graceful-
   failure judgment as V1 item 10, but in the gated context: does the error
   page leak anything, and does its design match the coming-soon page?
6. **Copy/paste**: select and copy the visible text — is the entirety of
   what's public just the name/tagline/copyright?
7. **Consistency**: compare the coming-soon page's look (colors, type,
   spacing) against what a professional would expect to precede a polished
   launch. Screenshot-based judgment.

Then: **free exploration** (short) + Emergent observations required.

<!-- ══════════════════ MISSION O1 ══════════════════ -->

# Mission O1 — Owner editing her site through /admin (core loop)

**Persona**: Jodi Daniel herself — a senior lawyer, sharp but NON-TECHNICAL:
comfortable with Word, Outlook, LinkedIn, and Squarespace-level tools. She
has never seen this admin before. No one is standing next to her. Every time
you have to stop and think "what does this field want?", that hesitation is
DATA — record it. Judge every label, every button, every hint by: would Jodi
know what to do without calling her son?

**Instance**:
- Public site: `http://127.0.0.1:4004/`
- Admin: `http://127.0.0.1:4004/admin/index-local.html`
- Fixture files for uploads: `fixtures/test-photo.jpg`
  in your instance directory.
- Remember (protocol): after Save, the public site rebuilds in ~2–10s —
  reload the public tab to check your change. Keep TWO tabs like a real
  owner: admin + site.
- Viewport 1440×900.

## Checklist (12 items)

1. **Arrival & orientation**: open the admin, get in (click through
   whatever login it shows). Screenshot the first screen. In persona: can
   you tell what each sidebar entry edits on YOUR site? Open the public
   site in the second tab; is the mapping section-editor → page-section
   obvious? Anything in the UI that would scare or confuse a lawyer
   (developer jargon, mystery buttons)? What does "Quick add" offer, and
   does everything it lists make sense for YOUR site?
2. **Edit the tagline**: Header/Hero → change the tagline to
   `Digital Health Law & Policy Leader — TEST EDIT` (type it; keep the em
   dash and ampersand). Save. Verify on the public site (reload). Then edit
   it BACK exactly, save, verify. Was it obvious the save worked (any
   confirmation)? How did you know the site updated — and would Jodi know
   to reload the other tab, or does anything tell her?
3. **Edit a bio paragraph**: About → change one word in one bio paragraph,
   save, verify on site, change it back, save, verify. Judge the list-of-
   paragraphs editing UI: is adding/reordering/removing a paragraph
   discoverable? (Look, hover — don't guess from docs.)
4. **Unsaved-changes safety**: make an edit, do NOT save, and try to leave
   (click a different collection in the sidebar; also try browser Back).
   Does anything warn you? Can you lose work silently? Then discard/recover
   per whatever the UI offers.
5. **Add a new Expertise card**: create one titled `Test Area — DELETE ME`,
   any short description. The "Order" field: as Jodi, what number do you
   put, and why — does the UI tell you, or do you have to already know? Put
   `99`. Save; verify where it appears on the site (position = expectation?).
6. **Reorder by weight**: change your test card's Order to `1`. Save.
   Verify it moved on the site. In persona: is number-based ordering
   workable for you, or did you expect drag-and-drop? Did the admin LIST
   reorder to match?
7. **Delete flows**: delete the test Expertise card (find the way; note
   how discoverable and how scary/safe it feels — confirmation?). Verify
   it's gone from the site.
8. **Edit a media item + validation**: Media Items → open the FDA
   generative-AI entry. Change the Article URL to `not a url` and try to
   save — what stops you, and is the message understandable? Fix it back to
   what it was (retype it carefully from what's shown). Then look at the
   "Archived PDF" and "Publish this PDF on the public website" fields. With
   the box UNTICKED, save and open the item's public page: is there any
   trace of the PDF? Now tick the box, save, and look again — does a
   download button appear, and does its label read sensibly for this item?
   (The file itself only reaches the website once a deploy publishes it out
   of the private archive, so on a local instance expect the link to 404 —
   note whether anything warns you about that.) Untick the box and save.
9. **Change the photo**: About → Profile Photo → replace with
   `fixtures/test-photo.jpg` through the UI (media library flow). Save,
   verify on site (even if the image is the same picture, verify the flow
   and note what the media library felt like — filenames, previews, any
   clutter?). Judge: would Jodi trust she picked the right image?
10. **Site Settings — the launch lever**: open Site Settings. In persona,
    read the "Site Live" control and its hint: do you understand EXACTLY
    what flipping it does, and how consequential it is? Flip it OFF, save,
    reload the public site — what do you see? Flip it back ON, save, verify
    the full site is back. Any moment of fear ("did I just break my
    site?") is a finding. Also read the rest of Settings (coming-soon
    fields, footer, section headings): is it clear which of these are live
    on the site right now vs. dormant?
11. **New media item end-to-end**: create a new Media Item: category
    `Press & News`, title `Test Coverage Item — DELETE ME`, source
    `Testing Weekly`, Article URL `https://example.com/story`, Order `9`.
    Save. Find it on the public site (right category? right position?),
    open its page, check the action button. Then delete the item in admin
    and verify both the section listing and the item's own URL are gone
    (reload the item URL — what do you get now, and would that worry an
    owner who had shared the link?).
12. **Sidebar search**: use the admin's "Search all" for `HIPAA` and for
    `Wilson`. Are results useful for finding what to edit?

Wrap-up in persona (REQUIRED, in Summary): Could Jodi maintain this site
alone? Which single change would most improve her confidence?

Leave the content exactly as you found it (every test artifact deleted,
every reverted edit verified on the public site). State in Coverage that
you verified restoration — if anything could not be restored, mark it
loudly at the top of the report.

Then: **free exploration** of the admin (Media tab in the top bar, sorting,
view toggles, anything) + Emergent observations required.

<!-- ══════════════════ MISSION O2 ══════════════════ -->

# Mission O2 — Owner, full sweep + rough edges + phone admin

**Persona**: Same non-technical owner as O1 (read that framing in your
prompt's protocol), but this session is her SECOND week: she now pokes every
corner, pastes real-world text, and makes the mistakes busy people make.

**Instance**:
- Public site: `http://127.0.0.1:4005/`
- Admin: `http://127.0.0.1:4005/admin/index-local.html`
- Fixtures: `fixtures/test-photo.jpg` in your instance directory. (The PDF
  fixtures the old item 8 used are gone with the upload control it probed.)
- Two tabs (admin + site); site rebuilds ~2–10s after save.
- Viewport 1440×900 unless stated.

## Checklist (11 items)

1. **Open all nine editors** (Expertise, Experience, Accomplishments, Media
   Items, Education, Header/Hero, About, Contact, Site Settings), screenshot
   each. For each: do the field labels/hints tell Jodi enough? Note every
   label you had to think twice about, and every field whose effect on the
   page you couldn't predict. (Don't save anything in this pass.)
2. **Realistic legal text**: In Experience, edit one entry's Description to a
   sentence containing: an ampersand, "§ 1798.100", a quoted phrase in
   double quotes, an apostrophe ("Daniel's"), and an em dash — typed as
   characters. Save; verify EVERY character renders correctly on the site
   (no &amp;, no mangled quotes). Restore the original text (retype from
   what it showed before — screenshot it first), save, verify.
3. **Long-content stress via UI**: Give one Expertise card a very long
   description (5–6 sentences, typed or pasted via keyboard). Save; look at
   the site: does the card grow gracefully next to its neighbors, or wreck
   the grid? Screenshot. Restore, save, verify.
4. **Contact links list**: Add a third contact link: label `Email`, URL
   `mailto:hello@example.com`, icon `email`. Save; verify the button appears
   with an appropriate icon and that activating it looks like an email
   action (don't worry about a mail app existing; judge label/icon/href
   plausibility). Judge the list-editing UI (add/reorder/remove
   affordances). Then delete the link, save, verify it's gone.
5. **In-page nav edit**: About → In-Page Nav Links: rename label `Media` to
   `Press`, save, check the site nav updated. Then set that link's anchor to
   `presss` (typo) and save: click it on the site — what happens? As Jodi,
   would you notice you broke it, and would you know why? Restore label
   `Media` + anchor `media`, save, verify the jump works again.
6. **Section headings ripple**: Site Settings → change "Media Heading" to
   `In the Press`, save. Check (a) the section heading on the home page and
   (b) open ANY media item's own page and look at its back link — did the
   wording follow? Restore `Publications & Media`, save, verify both spots.
7. **Category select**: In a Media item, open the Category dropdown; can
   Jodi add a category of her own from here, or only pick? (Just observe
   and judge; don't force anything.) Is the fixed list what she'd expect?
8. **The PDF permission gate**: Open a media entry that has an "Archived
   PDF" file name filled in (e.g. `1-fda-amicus.pdf`) and leave "Publish
   this PDF on the public website" UNTICKED. Save; open the item's public
   page — is there any sign of the PDF at all? (There should be none: no
   button, and no PDF file name anywhere in the page source.) Now, WITHOUT
   ticking anything, answer as Jodi: from the field label and hint alone,
   can you tell what ticking that box would do, and who is supposed to
   decide? Then type `notes.txt` into the Archived PDF field and try to
   save — does anything stop you, and does the message explain why? Restore
   the original file name and leave the box unticked.

   (This replaces an older "upload a .txt through the PDF Copy control"
   probe. There is no upload control any more: the PDF bytes live in a
   private S3 archive, never in this public repo, and the field names an
   object there. See docs/CONTENT-MODEL.md, "Archived PDFs".)
9. **Number-field mischief**: Set an Education entry's Order to `0`, save,
   observe placement on site; then try clearing the Order field entirely
   and saving — does the admin allow it, and what happens on the site's
   ordering? Restore the original number, save, verify.
10. **Phone admin**: new context at 390×844 (touch): open the admin, get to
    Media Items, open an entry, make a trivial edit (add and remove a
    character), Save. Judge honestly: could Jodi fix a typo from her phone
    in a taxi? Screenshot the editor, the sidebar, and the entry list at
    phone size; note anything unusable (buttons off-screen, sidebar
    covering content, keyboard-covered fields).
11. **The site→admin direction**: On the public site, imagine spotting a
    typo in an Accomplishment. Is there ANY visible route from the public
    page to the editor (any admin link, any hint)? If you were Jodi, how
    would you get from seeing the typo to fixing it? (Type the /admin URL
    like she'd have to; judge whether needing to remember it is
    acceptable.) Note: on this local copy use /admin/index-local.html; the
    real site serves /admin — judge the concept, not the exact URL.

Wrap-up (REQUIRED, in Summary): the three roughest edges for a non-technical
owner, ranked.

Leave all content exactly as found (verify each restoration on the public
site; call out anything you couldn't restore at the top of REPORT.md).

Then: **free exploration** + Emergent observations required.

<!-- ══════════════════ MISSION O3 ══════════════════ -->

# Mission O3 — Owner: previewing my changes, and the status of my site

**Persona**: The same non-technical owner (a senior lawyer; Word/Outlook/
Squarespace-level comfort). This session is about one anxiety every owner
has: **"If I change something, how do I see it before/after it's live, and
how do I know where things stand?"** Every affordance you meet gets judged
by that question.

**Instance**:
- Public site: `http://127.0.0.1:4006/`
- Admin (real local editor): `http://127.0.0.1:4006/admin/index-local.html`
- Workflow rehearsal surface: `http://127.0.0.1:4006/admin/index-test.html`
  — a platform-shipped, in-browser FAKE backend that exercises the
  PRODUCTION publishing model (Draft → In Review → Ready → Publish).
  Nothing there persists or touches the site; its collections are the
  platform's generic demo set (Posts, etc.), NOT this site's sections.
  There it is EXPECTED that the content list starts empty and that
  publishing does not change the public site — judge the MECHANICS,
  STATUSES, and LANGUAGE, never the content model or persistence.
- Viewport 1440×900. Two tabs like a real owner (admin + public site).
  After a Save in the real admin, the public site rebuilds in ~2–10s.

## Checklist (9 items)

1. **Editor chrome inventory (real admin)**: open Media Items → any entry.
   Screenshot the full editor. List every button/link/indicator you can see
   (toolbar and elsewhere). For each: would Jodi know what it does before
   clicking? Anything that looks like a status indicator? Anything that
   promises a preview?
2. **The floating "Live Preview" link (real admin)**: find it (note WHERE
   and WHEN it appears — entry list vs. entry editor). Read its hover
   hint. Click it from an entry editor: what opens? Now make a small edit
   to the entry (e.g. add "TEST" to the title), click Save, and look at
   the preview tab again (reload it too): does your change show up
   anywhere? Screenshot what the preview page actually displays. Judge:
   does this surface help Jodi see her change, mislead her, or just
   confuse? Then revert the edit (remove "TEST"), save, and confirm the
   revert on the public site.
3. **`/preview/` typed directly**: visit `http://127.0.0.1:4006/preview/`
   like a curious owner. What does it show, and does it explain itself?
4. **In-editor preview pane**: in the entry editor, is there a side-by-side
   live preview of the page (many CMSes have one)? If not: as Jodi, how DO
   you check what your edit will look like — does anything in the UI tell
   you the answer (open the site in another tab and reload), or did you
   only know because this mission told you? Judge the gap honestly.
5. **Deploy/status signals (real admin)**: hunt for anything that reports
   site/deployment status — pills, badges, banners, a "deployed" note, a
   colored dot — in the entry editor toolbar, entry list, and anywhere
   else. Make a save and watch for ~30s. Report exactly what exists and
   what it says, and what does NOT exist. (On the production admin there
   is machinery that shows deploy progress; this local editor may show
   some, none, or inert versions of it — document what an owner at this
   surface actually sees, precisely.)
6. **Workflow rehearsal (index-test.html)**: open the rehearsal surface,
   click through any login. Create a new Post (real typing: a title and a
   couple of body sentences), Save. Now: what STATUS does the UI say this
   content is in? Find the Workflow view (top navigation). Screenshot the
   board. Move your post through the columns to Ready — try dragging the
   card; if dragging fails, use whatever per-entry status control exists
   — then Publish it. At EACH step, narrate in persona what you believe
   just happened to "your site", and flag every place the UI's language
   leaves that unclear ("In review" — by whom? "Ready" — ready for what?
   "Publish" — live now? in a minute? where?). Note any preview/"Check
   for Preview" affordance you meet in these states and what it
   communicates (it may be inert here — report what you see).
7. **Unpublished-changes visibility (index-test.html)**: with a SECOND new
   post sitting in Draft, look at the Contents list: can you tell at a
   glance which items have unpublished changes and which are live? How?
8. **Deleting drafts vs published (index-test.html)**: delete your Draft
   post; then delete the Published one. Is the UI's language clear about
   WHAT you are deleting in each case (a draft? the live thing?), and how
   scary/safe does each feel? (Remember: mechanics only; nothing here is
   real.)
9. **"Where do things stand?" wrap-up (real admin)**: back on
   index-local.html — is there any single place Jodi could look to answer
   "what is my live site showing right now, and are any of my edits not
   yet on it?" Describe what you'd build/say if the answer is "nowhere".

Wrap-up (REQUIRED, in Summary): rank the three biggest gaps between what
this UI communicates about preview/status and what a non-technical owner
needs, and say which single change would help most.

Restore anything you changed in the REAL admin (item 2's revert) and
verify on the public site; index-test.html needs no cleanup (nothing
persists — but say so in your restoration statement).

Then: **free exploration** (both admin surfaces) + Emergent observations
required.
