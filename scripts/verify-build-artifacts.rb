#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "date"

# Lightweight build-artifact assertion for the platform-chrome fixes that
# jodidaniel.com owns (issues #28, #31). jodidaniel ships no JS/Playwright
# harness in-repo (the full e2e suite is checked out from the cms-platform
# gem at CI time and excluded from the build), so this is a self-contained
# pure-Ruby check — no extra toolchain beyond the Ruby already required to
# build the site.
#
#   bundle exec jekyll build
#   ruby scripts/verify-build-artifacts.rb
#
# It is TDD-shaped: it FAILS on a build of plain `main` (no /preview/, no
# 404.html, and the gem's "AD" logo leaking) and PASSES once the fixes land.
# `scripts/` is excluded from the Jekyll build (_config.yml), so this file is
# never published.

SITE = File.join(__dir__, "..", "_site")

failures = []
def check(failures, desc)
  ok = yield
  puts(ok ? "  ok   #{desc}" : "  FAIL #{desc}")
  failures << desc unless ok
end

def read(path)
  # Pin every read to UTF-8 explicitly rather than depending on the ambient
  # locale. A bare `File.read` decodes with Encoding.default_external, which
  # Ruby derives from LANG/LC_ALL; this repo is UTF-8 but a hosted session's
  # ambient locale can be unset/"C", which resolves to US-ASCII and raises
  # `ArgumentError: invalid byte sequence in US-ASCII` on the first non-ASCII
  # byte (an em dash, curly quote, etc. — both `_media/*.md` copy and this
  # script's own source have them) before a single check runs. The platform
  # already hit and fixed this same class of bug twice (its Decap render hook
  # and its config renderer) — same fix here: pass `encoding:` explicitly so
  # decoding no longer depends on what the container happens to export.
  File.exist?(path) ? File.read(path, encoding: "utf-8") : nil
end

preview = File.join(SITE, "preview", "index.html")
notfound = File.join(SITE, "404.html")
logo = File.join(SITE, "assets", "images", "logo.svg")

puts "== #28 Live Preview + 404 =="
preview_html = read(preview)
check(failures, "_site/preview/index.html exists (admin Live Preview target)") { !preview_html.nil? }
check(failures, "/preview/ uses the gem preview shell (data-preview-root)") do
  preview_html&.include?("data-preview-root")
end
check(failures, "/preview/ is noindex,nofollow") do
  preview_html&.match?(/name="robots"\s+content="noindex,\s*nofollow"/)
end
# Guardrail: the preview surface must render NO gated bio content. The home
# layout's bio copy arrives at edit time via postMessage, never baked into
# the shell. Assert a few bio markers from mockup.html are absent.
%w[
  Wilson\ Sonsini
  Crowell\ &\ Moring
  nationally\ recognized\ leader
  digital\ health\ law
].each do |marker|
  check(failures, "/preview/ does NOT leak gated bio text: #{marker.inspect}") do
    preview_html && !preview_html.include?(marker)
  end
end

notfound_html = read(notfound)
check(failures, "_site/404.html exists (friendly not-found, not S3 NoSuchKey)") { !notfound_html.nil? }
check(failures, "404.html links back to / (home)") do
  notfound_html&.match?(%r{href="/?"})
end
# Scope the no-blog assertion to the 404 BODY (the page-content actions the
# site owns), NOT the gem's site-wide header nav — that "Blog" link is shared
# gem chrome present on every default-layout page (incl. /preview/), out of
# scope for #28. jodidaniel has no blog, so the 404 body must not add one.
notfound_body = notfound_html && notfound_html[/<main.*?<\/main>/m]
check(failures, "404.html body has NO /blog/ link (single-page bio, no blog)") do
  notfound_body && !notfound_body.include?("/blog/")
end
check(failures, "404.html is noindex,nofollow") do
  notfound_html&.match?(/name="robots"\s+content="noindex,\s*nofollow"/)
end
# 404 chrome must be generic, never marketing/bio copy.
check(failures, "404.html copy is generic chrome (says 'not found')") do
  notfound_html&.downcase&.include?("not found")
end

puts "== #31 Jodi's logo (no 'AD' leak) =="
logo_svg = read(logo)
check(failures, "_site/assets/images/logo.svg exists (site file shadows the gem)") { !logo_svg.nil? }
check(failures, "logo is Jodi's 'JD' mark") { logo_svg&.include?(">JD<") }
check(failures, "logo is NOT the gem's 'AD' (Adam Daniel) mark") do
  logo_svg && !logo_svg.include?(">AD<")
end
# The rendered admin config must resolve logo_url to the site's own asset.
admin_cfg = read(File.join(SITE, "admin", "config.yml"))
check(failures, "admin config.yml logo_url -> <site>/assets/images/logo.svg") do
  admin_cfg&.include?("logo_url: https://jodidaniel.com/assets/images/logo.svg")
end

puts "== media items resolve (no 404) =="
# Regression guard for the bug where EVERY media link 404'd.
#
# _layouts/home.html links each media item with {{ item.url }}. For a Jekyll
# collection document `url` is the document's OWN address — Jekyll's
# DocumentDrop defines `url`, which shadows any front-matter `url:` key — so
# that link can only ever be /media/<slug>/. While the collection was
# `output: false` that address was never written and all 15 links 404'd
# (proven on preview-pr176 before the fix). The outbound article link now
# lives in `article_url`, and each item renders a real page.
media_src = Dir[File.join(__dir__, "..", "_media", "*.md")].sort
check(failures, "_media/ has entries to check") { !media_src.empty? }

media_src.each do |src|
  slug = File.basename(src, ".md")
  fm = read(src)
  # The trap that caused the outage: a front-matter `url:` is unreachable from
  # Liquid. Decap writes whatever admin/collections.site.yml names, so this
  # also catches the seam regressing to `url`.
  check(failures, "_media/#{slug}.md uses `article_url:`, not the shadowed `url:`") do
    fm.match?(/^article_url:/) && !fm.match?(/^url:/)
  end
  check(failures, "/media/#{slug}/ is a real page (home page links here)") do
    File.exist?(File.join(SITE, "media", slug, "index.html"))
  end
end

puts "== media date_display: a real date field, not baked into source =="
# Jodi's second ask: month + year on each media item. The date used to live
# inside `source` strings ("Bloomberg Law, 2018"), which is why the "no
# 4-digit year in source" check below exists -- once date_display renders
# beside source (_layouts/home.html, _layouts/media.html), a leftover year
# still in source would render the date TWICE. Parsed with the `yaml` stdlib
# (AGENTS.md), never a regex/line-scan over front matter.
#
# `date_display` is required to EXIST on every item (so a new entry can't
# silently omit it) but is allowed to be empty, a bare year, or "Ongoing" --
# those are real, deliberately-incomplete content states pending the owner
# filling them in from /admin, not build failures. See docs/CONTENT-MODEL.md.
MEDIA_DATE_DISPLAY_RE = /\A(Ongoing|(January|February|March|April|May|June|July|August|September|October|November|December) \d{4}|\d{4})\z/
undated_media = []
media_src.each do |src|
  slug = File.basename(src, ".md")
  raw = read(src)
  fm_match = raw && raw.match(/\A---\s*\n(.*?)\n---\s*\n?/m)
  fm = fm_match && YAML.safe_load(fm_match[1])
  fm = {} unless fm.is_a?(Hash)

  check(failures, "_media/#{slug}.md has a `date_display` key (may be empty)") { fm.key?("date_display") }

  date_display = fm["date_display"].to_s
  unless date_display.empty?
    check(
      failures,
      "_media/#{slug}.md date_display #{date_display.inspect} is Month YYYY, a bare year, or \"Ongoing\""
    ) { date_display.match?(MEDIA_DATE_DISPLAY_RE) }
  end

  source = fm["source"].to_s
  check(failures, "_media/#{slug}.md source #{source.inspect} carries no 4-digit year (date lives in date_display)") do
    !source.match?(/\d{4}/)
  end

  # "Lacks a month" = empty, or a bare year with no month. "Ongoing" is a
  # deliberate final answer (2-data-advisor-blog.md's ongoing blog), not a
  # gap waiting on the owner, so it is NOT flagged here.
  undated_media << slug if date_display.empty? || date_display.match?(/\A\d{4}\z/)
end

if undated_media.empty?
  puts "  ok   every media item's date_display has a month (or is \"Ongoing\")"
else
  puts "  note #{undated_media.length} media item(s) still need a month added to date_display " \
       "(empty or bare-year today) -- not a failure, closes itself when the owner fills them in " \
       "from /admin:"
  undated_media.sort.each { |slug| puts "       - #{slug}" }
end

puts "== issue #196: About nav anchors must resolve to a real section id =="
# `admin/collections.site.yml` turned `anchor` from a free-text string into a
# `select` over the destination sections, which stops a NEW typo through the
# UI. It does NOT catch a bad anchor already committed, one introduced by a
# direct file edit, or a section id renamed in _layouts/home.html while
# _data/about.yml still names the old one -- the more likely real-world
# break. So this asserts the BUILT artifact, not the source: for every entry
# in _data/about.yml's `nav`, the built home page must contain a real
# `<section id="...">` matching that entry's `anchor`. Parsed with the `yaml`
# stdlib (AGENTS.md) -- never a regex/line-scan over the data file.
about_yaml = YAML.safe_load(read(File.join(__dir__, "..", "_data", "about.yml")) || "") || {}
nav_entries = about_yaml["nav"].to_a
check(failures, "_data/about.yml has nav entries to check (issue #196)") { !nav_entries.empty? }

home_html_for_nav = read(File.join(SITE, "index.html"))
built_section_ids = home_html_for_nav.to_s.scan(/<section\s+id="([a-z-]+)"/).flatten

if built_section_ids.empty?
  # Vacuous while site_live is false: the gate (_layouts/home.html) hides
  # every section, so the built page has nothing to check anchors against.
  # Same posture as the PDF-checks note below -- say so rather than let a
  # pass here imply coverage it doesn't have.
  puts "  note site_live is false (or no sections rendered) -- nav-anchor id checks did NOT"
  puts "       run. Flip site_live: true and rebuild to arm them."
else
  nav_entries.each do |entry|
    anchor = entry.is_a?(Hash) ? entry["anchor"].to_s : ""
    label = entry.is_a?(Hash) ? entry["label"].to_s : ""
    check(
      failures,
      "About nav entry #{label.inspect} (anchor #{anchor.inspect}) resolves to a built " \
      "section id -- valid ids: #{built_section_ids.sort.inspect}"
    ) { built_section_ids.include?(anchor) }
  end
end

puts "== media nav label matches the section heading =="
# label and settings.section_headings.media_heading are separate strings by
# design (a nav label may be shorter than a headline) but must name the SAME
# thing -- "Media" described a category that no longer exists now that the
# section is split into what she wrote and what was written about her.
# Scoped to the `media` entry only: the other six nav labels are deliberately
# short forms of their headings ("Expertise" vs "What Jodi Works On") and
# that's fine -- this check must not catch them. Reuses `about_yaml` /
# `nav_entries`, already parsed with the `yaml` stdlib above; runs
# unconditionally (unlike the anchor checks above) since it compares two
# data files, not the built page.
settings_yaml_for_nav_label = YAML.safe_load(read(File.join(__dir__, "..", "_data", "settings.yml")) || "") || {}
media_heading = settings_yaml_for_nav_label.dig("section_headings", "media_heading").to_s
media_nav_entry = nav_entries.find { |e| e.is_a?(Hash) && e["anchor"] == "media" }
media_nav_label = media_nav_entry.is_a?(Hash) ? media_nav_entry["label"].to_s : nil
check(
  failures,
  "_data/about.yml media nav label #{media_nav_label.inspect} == " \
  "settings.section_headings.media_heading #{media_heading.inspect}"
) { !media_nav_entry.nil? && media_nav_label == media_heading }

puts "== issues #194 / #195: admin seam (link_label, pdf_label, .pdf pattern) =="
# Parsed with the `yaml` stdlib, never a regex/line-scan (AGENTS.md) — a regex
# over this flow-mapping seam can't tell `pattern:` apart from `hint:` text
# that happens to mention "pdf", and it can't see a field that moved lines.
seam_text = read(File.join(__dir__, "..", "admin", "collections.site.yml"))
seam_yaml = seam_text && YAML.safe_load(seam_text)
media_seam = seam_yaml.is_a?(Array) ? seam_yaml.find { |c| c.is_a?(Hash) && c["name"] == "media" } : nil
check(failures, "admin seam parses as YAML and has a `media` collection") { !media_seam.nil? }
media_seam_fields = (media_seam && media_seam["fields"]).to_a.each_with_object({}) do |f, h|
  h[f["name"]] = f if f.is_a?(Hash)
end

# The PDF BYTES must never enter this repo. jodidaniel.com is PUBLIC, so a
# committed PDF of a third-party article is world-readable at
# raw.githubusercontent.com regardless of what the site renders — and git
# history is immutable, so a later `git rm` does not take it back. The archive
# is private S3; the seam names an OBJECT in it. A `file`/`image` widget here
# would quietly restore the repo-upload path, so assert its absence, not just
# the new field's presence. See docs/CONTENT-MODEL.md, "Archived PDFs".
pdf_field = media_seam_fields["pdf_archive_file"]
check(failures, "admin seam names the archived PDF and offers NO repo upload") do
  pdf_field && pdf_field["widget"] == "string" && media_seam_fields["pdf"].nil?
end
check(failures, "admin seam's `pdf_archive_file` validates a `.pdf` suffix (issue #195)") do
  pattern = pdf_field && pdf_field["pattern"]
  pattern.is_a?(Array) && pattern.length == 2 && pattern[0].is_a?(String) &&
    pattern[0].include?(".pdf$") && !pattern[1].to_s.empty?
end
check(failures, "admin seam offers the `pdf_public` gate, defaulting to OFF") do
  f = media_seam_fields["pdf_public"]
  !f.nil? && f["widget"] == "boolean" && f["default"] == false
end

check(failures, "admin seam offers `link_label` on media entries, and it's optional (issue #194)") do
  f = media_seam_fields["link_label"]
  !f.nil? && f["required"] == false
end
check(failures, "admin seam offers `pdf_label` on media entries, and it's optional (issue #194)") do
  f = media_seam_fields["pdf_label"]
  !f.nil? && f["required"] == false
end
check(failures, "admin seam offers `date_display` on media entries, and it's optional") do
  f = media_seam_fields["date_display"]
  !f.nil? && f["required"] == false
end

# Every media link the home page actually renders must resolve to a built file.
# Vacuous while site_live is false (the gate hides the section) — the per-item
# page assertions above cover both gate states.
home_html = read(File.join(SITE, "index.html"))
home_media_links = home_html.to_s.scan(%r{href="(/media/[^"]*)"}).flatten.uniq
home_media_links.each do |href|
  check(failures, "home page link #{href} resolves in _site") do
    File.exist?(File.join(SITE, href.sub(%r{\A/}, ""), "index.html"))
  end
end

# Each built item page must carry its outbound article link, and the PDF link
# whenever the entry has one.
#
# The article-link SVG (globe icon, path starts "M11.99 2C6.47 2 2 6.48…") and
# the PDF-link SVG (document icon, path starts "M19 3H5c-1.1…") are each
# used exactly once in _layouts/media.html, so the text immediately after
# either one's closing </svg> and before the closing </a> IS that button's
# rendered label — this is how the two checks below read the label Liquid
# actually chose, from the built HTML, rather than re-deriving it in Ruby and
# risking the two maps drifting apart while still agreeing with each other.
ARTICLE_LABEL_RE = /M11\.99 2C6\.47 2 2 6\.48 2 12s4\.47.*?<\/svg>\s*([^<]+?)\s*<\/a>/m
PDF_HREF_RE = /href="([^"]+)"[^>]*>\s*<svg[^>]*><path d="M19 3H5c-1\.1/m
pdf_public_checks = 0
pdf_gated_checks = 0
article_labels = {} # slug => rendered label text, ungated pages only
media_src.each do |src|
  slug = File.basename(src, ".md")
  page = read(File.join(SITE, "media", slug, "index.html"))
  next if page.nil?
  gated = page.include?("noindex,nofollow")
  src_fm = read(src)
  article = src_fm[/^article_url:\s*"?([^"\n]+)"?/, 1].to_s.strip
  pdf_key = src_fm[/^pdf_archive_file:\s*"?([^"\n]+?)"?\s*$/, 1].to_s.strip
  # Only a literal `true` opens the gate; anything else (absent, false,
  # "false", empty) keeps it shut — mirrors the layout's `== true` test.
  pdf_public = src_fm[/^pdf_public:\s*(\S+)\s*$/, 1].to_s.strip == "true"
  if gated
    # Gate closed: the item page must be the coming-soon shell only.
    check(failures, "/media/#{slug}/ leaks no bio content while gated") do
      !page.include?(article) && !page.include?("section-title")
    end
  else
    check(failures, "/media/#{slug}/ links out to its article_url") do
      !article.empty? && page.include?(article)
    end
    label = page[ARTICLE_LABEL_RE, 1]
    article_labels[slug] = label unless article.empty?
    unless pdf_key.empty?
      if pdf_public
        pdf_public_checks += 1
        href = "/media-pdfs/#{pdf_key}"
        check(failures, "/media/#{slug}/ links to its published PDF (#{href})") do
          page.include?(href)
        end
        # Issue #195, belt half: the gate is open, so the layout's has_pdf
        # guard let the button through — and the href it RENDERED (not just the
        # front-matter string) must still end in `.pdf`. This catches the guard
        # regressing even if the seam pattern still blocks new saves.
        check(failures, "/media/#{slug}/'s rendered PDF href ends in .pdf") do
          h = page[PDF_HREF_RE, 1]
          !h.nil? && h.downcase.end_with?(".pdf")
        end
        # Ticking the box renders a download button; if nothing put the file
        # under _site/media-pdfs/ the button is a confident 404. The publish
        # step that copies an opted-in object out of the private archive is
        # platform-side (cms-platform), so until a site's deploy runs it this
        # assertion is what stops the box being ticked into a broken link
        # rather than a working download.
        check(failures, "published PDF #{href} exists in _site") do
          File.exist?(File.join(SITE, "media-pdfs", pdf_key))
        end
      else
        pdf_gated_checks += 1
        # THE assertion this feature turns on. An archived PDF that has not
        # been cleared for republication must leave NO trace on the public
        # page: no button, no href, and not even the file name in a comment or
        # a JSON-LD blob. Asserting only "no button" would pass a page that
        # still leaked a guessable URL, which is the failure this gate exists
        # to prevent.
        check(failures, "/media/#{slug}/ withholds its ungated PDF (#{pdf_key})") do
          !page.include?("/media-pdfs/") && !page.include?(pdf_key) &&
            page[PDF_HREF_RE, 1].nil?
        end
      end
    end
  end
end

# Issue #194 regression guard: before the fix, EVERY item said "Read the
# article" regardless of category — a podcast, a Supreme Court brief PDF, and
# a conference talk all rendered the same wrong verb. Assert the category
# default actually reached the built HTML, not just the layout source: at
# least one non-default label must appear, and (since the catalogue carries
# at least one `Podcasts & Interviews` and one `Briefs, Testimony & Reports`
# entry — see _media/1-ai-health-care-hipaa.md and _media/1-fda-amicus.md) at
# least two DISTINCT labels must appear across the built, ungated pages.
distinct_labels = article_labels.values.compact.uniq
# ...and "ungated" in that sentence is load-bearing, which is why these two are
# guarded rather than asserted flat. A media item's whole <article> -- the
# outbound-link button included -- sits inside `{% if live %}`, so a GATED build
# renders zero labels and both checks below fail for a reason that is not a
# defect. Gated is the normal state of this site until the copy sign-off (issue
# #26), so left unguarded they made a clean tree report failure on every run,
# which is the fastest way to teach someone to stop reading this script's
# output. Announce the vacuity instead -- the same contract the PDF and
# nav-anchor groups follow below and above.
if article_labels.empty?
  puts "  note site_live is false (or no media pages rendered) -- the issue #194"
  puts "       outbound-link label checks did NOT run. Flip site_live: true and"
  puts "       rebuild to arm them."
else
  check(failures, "built media pages render more than one outbound-link label (issue #194)") do
    distinct_labels.length >= 2
  end
  check(failures, "built media pages do NOT all say \"Read the article\" (issue #194)") do
    distinct_labels != ["Read the article"]
  end
end

# The PDF assertions above are CONDITIONAL on an entry carrying a
# `pdf_archive_file`, and they split two ways. Say which half actually ran:
# "All build-artifact assertions passed" over zero of either is the green light
# wired to nothing that AGENTS.md warns about. Neither zero is a FAILURE — a
# catalogue with no archived PDFs, or none yet cleared for republication, are
# both legitimate content states — but the coverage claim has to be honest.
if pdf_gated_checks.zero? && pdf_public_checks.zero?
  puts "  note no media entry carries a `pdf_archive_file`, so NEITHER the withhold"
  puts "       assertion nor the publish assertion ran. A pass here is not evidence"
  puts "       the PDF chain works — see docs/CONTENT-MODEL.md, \"Archived PDFs\"."
else
  puts "  ok   PDF gate exercised: #{pdf_gated_checks} withheld, #{pdf_public_checks} published"
  if pdf_public_checks.zero?
    puts "  note no entry has `pdf_public: true`, so the PUBLISH half did not run."
    puts "       The withhold half (the default, and the security-relevant one) did."
  end
end

# Repo-wide, and deliberately not scoped to _media: the invariant is that PDF
# BYTES never land in this PUBLIC repo at all, from any path — an editor upload,
# a hand-copied offprint, a well-meaning `assets/` commit. _site is excluded
# because a build legitimately materialises opted-in PDFs there; it is never
# committed (.gitignore).
pdf_bytes_in_repo = Dir.glob(File.join(__dir__, "..", "**", "*.pdf"), File::FNM_CASEFOLD)
                       .map { |f| File.expand_path(f) }
                       .reject { |f| f =~ %r{/(_site|\.git|\.cms-platform|node_modules|vendor|e2e)/} }
check(failures, "no PDF bytes are committed to this public repo") do
  pdf_bytes_in_repo.empty?
end
unless pdf_bytes_in_repo.empty?
  pdf_bytes_in_repo.first(5).each { |f| puts "       stray PDF: #{f}" }
end

puts "== Media: authored vs. appearances are separated =="
# The owner's request: separate media appearances/articles she is quoted in
# from things she authored/co-authored. The old flat five-category list mixed
# the two — Featured Articles held both a blog she writes AND an interview
# where a reporter quotes her, which read as if she'd written the interview.
# The five categories now live in two GROUPS (media_authored_cats /
# media_coverage_cats in _layouts/home.html) and are dual-maintained across
# THREE places: this seam's `category` options, those two lists in
# _layouts/home.html, and the `{% case page.category %}` default-label map in
# _layouts/media.html. Each leg below guards one of the three; the last group
# guards the actual invariant the owner asked for.
KNOWN_MEDIA_CATEGORIES = [
  "Articles & Commentary",
  "Briefs, Testimony & Reports",
  "Talks & Panels",
  "Podcasts & Interviews",
  "Press Coverage",
].freeze

# Leg 0: every _media/*.md's `category` is one of the five known values.
# Parsed with the `yaml` stdlib (AGENTS.md), never a regex/line-scan.
media_category_by_slug = {}
media_title_by_slug = {}
media_src.each do |src|
  slug = File.basename(src, ".md")
  raw = read(src)
  fm_match = raw && raw.match(/\A---\s*\n(.*?)\n---\s*\n?/m)
  fm = fm_match && YAML.safe_load(fm_match[1])
  fm = {} unless fm.is_a?(Hash)
  category = fm["category"]
  media_category_by_slug[slug] = category
  media_title_by_slug[slug] = fm["title"].to_s
  check(failures, "_media/#{slug}.md category #{category.inspect} is one of the five known values") do
    KNOWN_MEDIA_CATEGORIES.include?(category)
  end
end

# Leg 1 (the seam) vs leg 2 (the layout): the seam's `category` options must
# equal the UNION of _layouts/home.html's two category lists. The seam is
# parsed with YAML (reuses `media_seam_fields`, already parsed above); the
# layout is Liquid, not YAML, so its two lists are read by extracting the
# literal `split: "|"` string — the same text-level technique this script
# already uses elsewhere (ARTICLE_LABEL_RE, PDF_HREF_RE) to read templated
# content that isn't itself a structured format.
home_layout_src = read(File.join(__dir__, "..", "_layouts", "home.html"))
authored_cats_literal = home_layout_src && home_layout_src[/assign media_authored_cats = "([^"]*)" \| split: "\|"/, 1]
coverage_cats_literal = home_layout_src && home_layout_src[/assign media_coverage_cats = "([^"]*)" \| split: "\|"/, 1]
check(failures, "_layouts/home.html defines media_authored_cats and media_coverage_cats") do
  !authored_cats_literal.nil? && !coverage_cats_literal.nil?
end
authored_categories = authored_cats_literal.to_s.split("|")
coverage_categories = coverage_cats_literal.to_s.split("|")
layout_categories = (authored_categories + coverage_categories).sort

seam_category_field = media_seam_fields["category"]
seam_category_options = (seam_category_field && seam_category_field["options"]).to_a.sort
check(
  failures,
  "seam's category options == union of _layouts/home.html's two category lists -- " \
  "seam has #{seam_category_options.inspect}, layout has #{layout_categories.inspect}"
) { seam_category_options == layout_categories }

# Leg 3: _layouts/media.html's `{% case page.category %}` has a `when` for
# each of the five — this is the leg with no other guard today (the #194
# label map there was never cross-checked against anything until now).
media_layout_src = read(File.join(__dir__, "..", "_layouts", "media.html"))
media_layout_whens = media_layout_src.to_s.scan(/when "([^"]+)"/).flatten
KNOWN_MEDIA_CATEGORIES.each do |cat|
  check(failures, "_layouts/media.html's {% case page.category %} has a `when \"#{cat}\"`") do
    media_layout_whens.include?(cat)
  end
end

# The actual invariant the owner asked for: on the built home page, both
# group headings render, and every authored-group item's title appears
# BEFORE every coverage-group item's title. Vacuous while site_live is
# false (the gate hides the whole Media section) — same conditional posture
# as the other gated checks in this file (note, not a failure).
if home_html.to_s.include?('<section id="media"')
  settings_yaml_for_media = YAML.safe_load(read(File.join(__dir__, "..", "_data", "settings.yml")) || "") || {}
  authored_heading = settings_yaml_for_media.dig("section_headings", "media_authored_heading").to_s
  coverage_heading = settings_yaml_for_media.dig("section_headings", "media_coverage_heading").to_s

  check(failures, "built home page includes the authored-group heading #{authored_heading.inspect}") do
    !authored_heading.empty? && home_html.include?(authored_heading)
  end
  check(failures, "built home page includes the coverage-group heading #{coverage_heading.inspect}") do
    !coverage_heading.empty? && home_html.include?(coverage_heading)
  end

  authored_indices = media_category_by_slug.filter_map do |slug, cat|
    next unless authored_categories.include?(cat)
    title = media_title_by_slug[slug]
    home_html.index(title) if title && !title.empty?
  end
  coverage_indices = media_category_by_slug.filter_map do |slug, cat|
    next unless coverage_categories.include?(cat)
    title = media_title_by_slug[slug]
    home_html.index(title) if title && !title.empty?
  end

  check(failures, "built home page has both authored-group and coverage-group items to order") do
    !authored_indices.empty? && !coverage_indices.empty?
  end
  check(
    failures,
    "every authored-group item title appears BEFORE every coverage-group item title -- " \
    "authored max index #{authored_indices.max.inspect}, coverage min index #{coverage_indices.min.inspect}"
  ) do
    !authored_indices.empty? && !coverage_indices.empty? && authored_indices.max < coverage_indices.min
  end
else
  puts "  note site_live is false (or no <section id=\"media\"> rendered) -- the authored-vs-"
  puts "       coverage heading/ordering checks did NOT run. Flip site_live: true and rebuild"
  puts "       to arm them."
end

puts "== Upcoming Events (Jodi 2026-08-30 feedback) =="
# _events/ is a NEW folder collection (feedback item 3), ordered by
# `start_date` rather than `weight` like every sibling collection above --
# see the comment on `events:` in _config.yml. Front matter is parsed with
# the `yaml` stdlib (AGENTS.md), never a regex/line-scan.
events_src = Dir[File.join(__dir__, "..", "_events", "*.md")].sort
check(failures, "_events/ has entries to check") { !events_src.empty? }

EVENT_DATE_RE = /\A\d{4}-\d{2}-\d{2}\z/
events_by_slug = {}
events_src.each do |src|
  slug = File.basename(src, ".md")
  raw = read(src)
  fm_match = raw && raw.match(/\A---\s*\n(.*?)\n---\s*\n?/m)
  check(failures, "_events/#{slug}.md front matter parses as YAML") { !fm_match.nil? }
  next unless fm_match

  # `permitted_classes: [Date]` is load-bearing, not boilerplate. A bare
  # `YAML.safe_load` RAISES Psych::DisallowedClass the moment it meets an
  # unquoted `start_date: 2026-10-14` -- which is precisely the mistake the
  # next check exists to report. The script then died at this line with a raw
  # Psych backtrace instead of the one-line FAIL below, and, worse, took every
  # remaining assertion in this file down with it (the above-the-fold group
  # and the seam<->layout cross-check never ran), so a second unrelated
  # regression in the same run would have been invisible. Permitting Date here
  # lets the value through AS a Date so the `is_a?(String)` check can report it
  # properly and the run continues. Rescue anything else Psych can raise for
  # the same reason: a malformed entry must fail as a named assertion, never as
  # a stack trace.
  fm = begin
    YAML.safe_load(fm_match[1], permitted_classes: [Date])
  rescue Psych::Exception
    nil
  end || {}
  events_by_slug[slug] = fm

  check(failures, "_events/#{slug}.md front matter is a YAML mapping") { fm.is_a?(Hash) && !fm.empty? }
  next unless fm.is_a?(Hash)

  check(failures, "_events/#{slug}.md start_date is a String \"YYYY-MM-DD\" (not a YAML Date)") do
    # Decap's `string` widget always writes a quoted scalar, so YAML parses
    # it as a String -- but a hand edit that drops the quotes (`start_date:
    # 2026-09-17` bare) gets auto-resolved to a Ruby Date by YAML's
    # timestamp rule instead. `sort: 'start_date'` on a mix of Strings and
    # Dates compares mismatched types, so this has to stay a String on
    # every entry or the sort silently misorders (or raises) the moment one
    # entry drifts.
    fm["start_date"].is_a?(String) && fm["start_date"].match?(EVENT_DATE_RE)
  end
  check(failures, "_events/#{slug}.md has a non-empty title") do
    fm["title"].is_a?(String) && !fm["title"].strip.empty?
  end
  # The DocumentDrop trap (docs/CONTENT-MODEL.md, and the AGENTS.md list of
  # reserved front-matter keys): `url` and `date` are both DocumentDrop
  # accessors that shadow a same-named front-matter key before Liquid ever
  # sees it. That's exactly why this collection's fields are `event_url` and
  # `start_date`, never `url`/`date` -- and why a stray top-level `url:` or
  # `date:` here is a regression, not a style nit.
  check(failures, "_events/#{slug}.md has no top-level `url:` key (DocumentDrop shadow)") do
    !fm.key?("url")
  end
  check(failures, "_events/#{slug}.md has no top-level `date:` key (DocumentDrop shadow)") do
    !fm.key?("date")
  end
end

home_html_for_events = read(File.join(SITE, "index.html"))
if home_html_for_events && home_html_for_events.include?('<section id="events"')
  events_by_slug.each_value do |fm|
    title = fm["title"].to_s
    check(failures, "built home page includes event title #{title.inspect}") do
      home_html_for_events.include?(title)
    end
    date_display = fm["date_display"].to_s
    next if date_display.empty? # guarded {% if %} in the layout; nothing to find

    check(failures, "built home page includes event date_display #{date_display.inspect}") do
      home_html_for_events.include?(date_display)
    end
  end

  expected_order = events_by_slug.values.sort_by { |fm| fm["start_date"].to_s }.map { |fm| fm["title"].to_s }
  found_order = events_by_slug.values.map { |fm| fm["title"].to_s }
                               .select { |t| home_html_for_events.include?(t) }
                               .sort_by { |t| home_html_for_events.index(t) }
  check(
    failures,
    "events appear in the built page in start_date order -- found #{found_order.inspect}, " \
    "expected #{expected_order.inspect}"
  ) { found_order == expected_order }
else
  # Same conditional posture as the #196 nav-anchor check and the PDF checks
  # above: say out loud that this didn't run, rather than let an unrelated
  # pass (or an empty failures array) imply coverage the gate is hiding.
  puts "  note no <section id=\"events\"> in the built home page (site_live is false, or no"
  puts "       events) -- the built-page title/date_display/order checks did NOT run. Flip"
  puts "       site_live: true and rebuild to arm them."
end

puts "== Above the fold: blurb + nav (Jodi 2026-08-30 feedback) =="
# Feedback item 2: the one-sentence `lead` and the nav pills both have to
# land inside the first viewport; the full bio moves below them. The pixel
# measurement itself isn't reproducible in pure Ruby (that's what
# measure-fold.js is for -- see docs/CONTENT-MODEL.md) but the DOM ordering
# that makes it *possible* is, and that's what a careless future edit -- one
# that moves .intro-bio back above the nav, say -- would silently undo with
# no build error. This checks that ordering, not the pixels.
about_yaml_for_lead = YAML.safe_load(read(File.join(__dir__, "..", "_data", "about.yml")) || "") || {}
check(failures, "_data/about.yml has a non-empty `lead`") do
  about_yaml_for_lead["lead"].is_a?(String) && !about_yaml_for_lead["lead"].strip.empty?
end

home_html_for_fold = read(File.join(SITE, "index.html"))
lead_idx = home_html_for_fold&.index('class="intro-lead"')
nav_idx  = home_html_for_fold&.index('class="intro-nav"')
bio_idx  = home_html_for_fold&.index('class="intro-bio"')

if lead_idx && nav_idx && bio_idx
  check(failures, "built page: .intro-lead precedes .intro-bio (blurb sits above the bio)") do
    lead_idx < bio_idx
  end
  check(failures, "built page: .intro-nav precedes .intro-bio (nav sits above the bio)") do
    nav_idx < bio_idx
  end
else
  puts "  note site_live is false (or the About card didn't render, or bio is empty) -- the"
  puts "       intro-lead/intro-nav/intro-bio ordering check did NOT run. Flip site_live: true"
  puts "       and rebuild to arm it."
end

puts "== admin seam <-> layout section ids stay in step =="
# The `anchor` select's `options:` (site_about -> nav -> anchor, in the admin
# seam) is DUAL-MAINTAINED with the `<section id="...">` set _layouts/home.html
# actually renders -- see docs/CONTENT-MODEL.md's "About nav anchors are a
# closed set" section, and the comment on `anchor` in admin/collections.site.yml
# itself. A mismatch either offers a picker option nobody can jump to, or
# leaves a real section unreachable from the nav picker, with no build error
# either way. Reuses `seam_yaml`, already parsed above for the media-seam
# checks (`yaml` stdlib, never a regex/line-scan over this flow-mapping file).
site_about_seam = seam_yaml.is_a?(Array) ? seam_yaml.find { |c| c.is_a?(Hash) && c["name"] == "site_about" } : nil
check(failures, "admin seam has a `site_about` file collection") { !site_about_seam.nil? }

about_file_seam = site_about_seam && (site_about_seam["files"] || []).find { |f| f.is_a?(Hash) && f["name"] == "about" }
about_seam_fields = (about_file_seam && about_file_seam["fields"]).to_a

check(failures, "admin seam's site_about offers a `lead` field") do
  about_seam_fields.any? { |f| f.is_a?(Hash) && f["name"] == "lead" }
end

nav_seam_field = about_seam_fields.find { |f| f.is_a?(Hash) && f["name"] == "nav" }
anchor_seam_field = (nav_seam_field && nav_seam_field["fields"]).to_a.find { |f| f.is_a?(Hash) && f["name"] == "anchor" }
anchor_seam_options = (anchor_seam_field && anchor_seam_field["options"]).to_a

home_html_for_ids = read(File.join(SITE, "index.html"))
all_section_ids = home_html_for_ids.to_s.scan(/<section\s+id="([a-z-]+)"/).flatten.uniq

if all_section_ids.empty?
  puts "  note site_live is false (or no sections rendered) -- the admin-seam <-> layout"
  puts "       section-id cross-check did NOT run. Flip site_live: true and rebuild to arm it."
else
  expected_ids = (all_section_ids - ["about"]).sort
  actual_options = anchor_seam_options.sort
  check(
    failures,
    "admin seam's anchor options == built section ids minus \"about\" -- " \
    "seam has #{actual_options.inspect}, built page has #{expected_ids.inspect}"
  ) { actual_options == expected_ids }
end

events_seam = seam_yaml.is_a?(Array) ? seam_yaml.find { |c| c.is_a?(Hash) && c["name"] == "events" } : nil
check(failures, "admin seam has an `events` folder collection") { !events_seam.nil? }
events_seam_field_names = (events_seam && events_seam["fields"]).to_a.filter_map { |f| f["name"] if f.is_a?(Hash) }.sort
expected_event_fields = %w[date_display event_url location org session start_date title].sort
check(
  failures,
  "admin seam's events fields == what the layout reads -- seam has #{events_seam_field_names.inspect}, " \
  "expected #{expected_event_fields.inspect}"
) { events_seam_field_names == expected_event_fields }

puts
if failures.empty?
  puts "All build-artifact assertions passed."
  exit 0
else
  puts "#{failures.size} assertion(s) FAILED:"
  failures.each { |f| puts "  - #{f}" }
  exit 1
end
