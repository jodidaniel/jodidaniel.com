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
#
# TWO PASSES (issue #306). While `site_live` is false the coming-soon gate
# hides every section and every media page, so most content groups below have
# nothing to read on the committed build: a green run there said nothing about
# what launch would ship. So, after checking the committed build in `_site`,
# this script copies the tracked source files (`git ls-files`, so no ignored
# local content) into a temporary directory OUTSIDE the repo (no `.git`, so
# nothing run there can push), forces `site_live: true` in that copy only,
# adds the synthetic PDF entries in PDF_FIXTURES, builds it, and re-runs every
# assertion against that build with `--open-pass`. On that pass a group the
# gate would hide is a FAILURE, not a note. The copy and its build are deleted
# when the run ends, so nothing in them can be deployed, and the committed
# `_data/settings.yml` is never written (asserted below).
#
#   ruby scripts/verify-build-artifacts.rb --open-pass <source-copy> <its _site>
#
# is the internal re-entry the first pass uses; run the script bare.

require "fileutils"
require "rbconfig"
require "tmpdir"
require_relative "media_rules"

REPO_ROOT = File.expand_path("..", __dir__)
OPEN_PASS = ARGV[0] == "--open-pass"
ROOT = OPEN_PASS ? File.expand_path(ARGV.fetch(1)) : REPO_ROOT
SITE = OPEN_PASS ? File.expand_path(ARGV.fetch(2)) : File.join(REPO_ROOT, "_site")

# The archived-PDF suffix rule (issue #305): a lowercase `.pdf`, compared
# case-sensitively. This is the platform's rule end to end -- the shared
# `pdf_archive_file` field's `[.]pdf$` pattern and publish-opted-in-pdfs.sh's
# `^[A-Za-z0-9._-]+\.pdf$` both reject `report.PDF` -- so the layout (no
# `downcase`) and this script follow it rather than accepting any casing.
PDF_SUFFIX_RE = /\.pdf\z/

# The stricter rule the DEPLOY applies (cms-platform's
# scripts/publish-opted-in-pdfs.sh, at the tag in platform.lock): an opted-in
# `pdf_archive_file` is copied out of the private archive only when it matches
# `^[A-Za-z0-9._-]+\.pdf$` and contains no `..`; any other name aborts the
# deploy. The admin field's `[.]pdf$` is looser (it would accept `my file.pdf`
# or `a/b.pdf`), so THIS is where the stricter rule is enforced before deploy.
# `\A...\z`, not `^...$`: a name with a newline in it must not pass.
DEPLOY_PDF_KEY_RE = /\A[A-Za-z0-9._-]+\.pdf\z/

def deploy_accepts_pdf_key?(key)
  key.match?(DEPLOY_PDF_KEY_RE) && !key.include?("..")
end

# An entry's front matter parsed as the deploy script parses it (a real YAML
# parser, the same split and options), so "is this entry opted in" means the
# same thing here as at deploy time. Nil when there is none or it does not parse.
def media_front_matter(path)
  parts = File.read(path, encoding: "utf-8").split(/^---\s*$/, 3)
  return nil if parts.length < 3

  fm = YAML.safe_load(parts[1], aliases: true, permitted_classes: [Date, Time])
  fm.is_a?(Hash) ? fm : nil
rescue Psych::SyntaxError, Psych::DisallowedClass
  nil
end

# Synthetic `_media` entries the open-gate pass adds to its disposable copy, so
# the withhold path, the publish path and the suffix rule all run even though
# no real entry is `pdf_public: true` today. [slug, pdf_archive_file,
# pdf_public]. Never written into the repo.
PDF_FIXTURE_PREFIX = "zz-verifier-fixture-"
PDF_FIXTURES = [
  ["#{PDF_FIXTURE_PREFIX}withheld", "verifier-fixture-withheld.pdf", false],
  ["#{PDF_FIXTURE_PREFIX}published", "verifier-fixture-published.pdf", true],
  ["#{PDF_FIXTURE_PREFIX}upper", "verifier-fixture-upper.PDF", true],
  ["#{PDF_FIXTURE_PREFIX}mixed", "verifier-fixture-mixed.Pdf", true],
  ["#{PDF_FIXTURE_PREFIX}no-suffix", "verifier-fixture-no-suffix", true],
  ["#{PDF_FIXTURE_PREFIX}pdf-txt", "verifier-fixture.pdf.txt", true],
].freeze

STATS = { executed: 0 }
failures = []
def check(failures, desc)
  STATS[:executed] += 1
  ok = yield
  puts(ok ? "  ok   #{desc}" : "  FAIL #{desc}")
  failures << desc unless ok
end

# A group whose content the coming-soon gate hides. On the committed build
# that is expected while `site_live` is false, so it is announced, not failed.
# On the open-gate pass the gate is forced open, so the same skip means the
# build does not render what launch would render: a failure.
def gate_hidden(failures, group)
  if OPEN_PASS
    check(failures, "#{group} ran against the open-gate build") { false }
  else
    puts "  note #{group} did NOT run on this build (site_live is false, so the"
    puts "       content is hidden); the open-gate pass below runs it."
  end
end

puts(OPEN_PASS ? "#### open-gate pass: site_live forced on in a disposable copy" : "#### committed-gate pass: _site")

# The site-verify reusable (platform-owned) runs only `jekyll build` and this script, so
# the unit tests for the rules this script applies run from here (issues #338, #339, #358).
# Committed pass only: the open-gate re-entry would repeat them.
unless OPEN_PASS
  puts "== unit tests: scripts/test-media-rules.rb =="
  $stdout.flush
  unit_tests_passed = system(RbConfig.ruby, File.join(__dir__, "test-media-rules.rb"))
  check(failures, "scripts/test-media-rules.rb passes (output above)") { unit_tests_passed == true }

  puts "== unit tests: scripts/test-admin-config.rb =="
  $stdout.flush
  admin_config_passed = system(RbConfig.ruby, File.join(__dir__, "test-admin-config.rb"))
  check(failures, "scripts/test-admin-config.rb passes (output above)") { admin_config_passed == true }
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
media_src = Dir[File.join(ROOT, "_media", "*.md")].sort
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
  # Jekyll builds `/media/:slug/` from its OWN slug of the file name, which drops
  # characters such as an em dash (issue #339), so the address is not the raw name.
  check(failures, "/media/#{MediaRules.page_slug(src, media_front_matter(src))}/ is a real page (home page links here)") do
    File.exist?(MediaRules.page_path(SITE, src, media_front_matter(src)))
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
# `date_display` is optional: absent, empty, a bare year, or "Ongoing" are all real,
# deliberately-incomplete content states pending the owner filling them in from
# /admin, not build failures. Absent counts the same as empty because Decap writes
# NO key for an optional text field left blank (issue #338). See docs/CONTENT-MODEL.md.
undated_media = []
media_src.each do |src|
  slug = File.basename(src, ".md")
  raw = read(src)
  fm_match = raw && raw.match(/\A---\s*\n(.*?)\n---\s*\n?/m)
  fm = fm_match && YAML.safe_load(fm_match[1])
  fm = {} unless fm.is_a?(Hash)

  date_display = MediaRules.optional_text(fm, "date_display")
  unless date_display.empty?
    check(
      failures,
      "_media/#{slug}.md date_display #{date_display.inspect} is Month YYYY, a bare year, or \"Ongoing\""
    ) { MediaRules.date_display_problem(fm).nil? }
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
about_yaml = YAML.safe_load(read(File.join(ROOT, "_data", "about.yml")) || "") || {}
nav_entries = about_yaml["nav"].to_a
check(failures, "_data/about.yml has nav entries to check (issue #196)") { !nav_entries.empty? }

home_html_for_nav = read(File.join(SITE, "index.html"))
built_section_ids = home_html_for_nav.to_s.scan(/<section\s+id="([a-z-]+)"/).flatten

if built_section_ids.empty?
  # Vacuous while site_live is false: the gate (_layouts/home.html) hides
  # every section, so the built page has nothing to check anchors against.
  # Same posture as the PDF-checks note below -- say so rather than let a
  # pass here imply coverage it doesn't have.
  gate_hidden(failures, "the issue #196 nav-anchor id checks")
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
settings_yaml_for_nav_label = YAML.safe_load(read(File.join(ROOT, "_data", "settings.yml")) || "") || {}
media_heading = settings_yaml_for_nav_label.dig("section_headings", "media_heading").to_s
media_nav_entry = nav_entries.find { |e| e.is_a?(Hash) && e["anchor"] == "media" }
media_nav_label = media_nav_entry.is_a?(Hash) ? media_nav_entry["label"].to_s : nil
check(
  failures,
  "_data/about.yml media nav label #{media_nav_label.inspect} == " \
  "settings.section_headings.media_heading #{media_heading.inspect}"
) { !media_nav_entry.nil? && media_nav_label == media_heading }

puts "== issues #194 / #195: rendered admin fields (link_label, pdf_label, .pdf pattern) =="
# Parsed with the `yaml` stdlib, never a regex/line-scan (AGENTS.md) — a regex
# over this flow-mapping seam can't tell `pattern:` apart from `hint:` text
# that happens to mention "pdf", and it can't see a field that moved lines.
seam_text = read(File.join(ROOT, "admin", "collections.site.yml"))
seam_yaml = seam_text && YAML.safe_load(seam_text)
media_seam = seam_yaml.is_a?(Array) ? seam_yaml.find { |c| c.is_a?(Hash) && c["name"] == "media" } : nil
check(failures, "admin seam parses as YAML and has a `media` collection") { !media_seam.nil? }
media_seam_fields = (media_seam && media_seam["fields"]).to_a.each_with_object({}) do |f, h|
  h[f["name"]] = f if f.is_a?(Hash)
end

# Shared platform fields are `$ref` nodes in the site-owned seam, so their
# actual Decap contract exists only in the rendered config. Read the build
# artifact the editor receives; continuing to inspect only the raw seam would
# mistake every shared field for a missing field.
admin_config = admin_cfg && YAML.safe_load(
  admin_cfg,
  permitted_classes: [Date],
  aliases: true
)
media_admin = admin_config.is_a?(Hash) ? admin_config.fetch("collections", []).find do |collection|
  collection.is_a?(Hash) && collection["name"] == "media"
end : nil
check(failures, "rendered admin config parses as YAML and has a `media` collection") { !media_admin.nil? }
media_admin_fields = (media_admin && media_admin["fields"]).to_a.each_with_object({}) do |field, fields|
  fields[field["name"]] = field if field.is_a?(Hash)
end

# The PDF BYTES must never enter this repo. jodidaniel.com is PUBLIC, so a
# committed PDF of a third-party article is world-readable at
# raw.githubusercontent.com regardless of what the site renders — and git
# history is immutable, so a later `git rm` does not take it back. The archive
# is private S3; the seam names an OBJECT in it. A `file`/`image` widget here
# would quietly restore the repo-upload path, so assert its absence, not just
# the new field's presence. See docs/CONTENT-MODEL.md, "Archived PDFs".
pdf_field = media_admin_fields["pdf_archive_file"]
check(failures, "rendered admin config names the archived PDF and offers NO repo upload") do
  pdf_field && pdf_field["widget"] == "string" && media_admin_fields["pdf"].nil?
end
# The field's own suffix rule, compiled once: the check below proves it is the
# case-sensitive rule (issue #305), and the per-entry loop further down holds
# every real entry's `pdf_archive_file` to it, so a hand edit that Decap never
# validated cannot slip a `.PDF` name past the editor's rule.
field_suffix_rule = begin
  pattern = pdf_field && pdf_field["pattern"]
  if pattern.is_a?(Array) && pattern.length == 2 && pattern[0].is_a?(String) && !pattern[1].to_s.empty?
    Regexp.new(pattern[0])
  end
rescue RegexpError
  nil
end
check(failures, "rendered `pdf_archive_file` validates a lowercase `.pdf` suffix, case-sensitively (issues #195, #305)") do
  suffix = field_suffix_rule
  !suffix.nil? &&
    suffix.match?("report.pdf") &&
    !suffix.match?("report.txt") &&
    !suffix.match?("reportxpdf") &&
    !suffix.match?("report.pdf.txt") &&
    !suffix.match?("report.PDF") &&
    !suffix.match?("report.Pdf") &&
    !suffix.match?("report")
end
check(failures, "rendered admin config offers the `pdf_public` gate, defaulting to OFF") do
  f = media_admin_fields["pdf_public"]
  !f.nil? && f["widget"] == "boolean" && f["default"] == false
end

check(failures, "admin seam offers `link_label` on media entries, and it's optional (issue #194)") do
  f = media_seam_fields["link_label"]
  !f.nil? && f["required"] == false
end
check(failures, "rendered admin config offers `pdf_label` on media entries, and it's optional (issue #194)") do
  f = media_admin_fields["pdf_label"]
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
if OPEN_PASS
  check(failures, "built home page links to media item pages") { !home_media_links.empty? }
end
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
pdf_refused_checks = 0
article_labels = {} # slug => rendered label text, ungated pages only
media_src.each do |src|
  slug = File.basename(src, ".md")
  src_fm = read(src)
  article = src_fm[/^article_url:\s*"?([^"\n]+)"?/, 1].to_s.strip
  pdf_key = src_fm[/^pdf_archive_file:\s*"?([^"\n]+?)"?\s*$/, 1].to_s.strip
  # Only a literal `true` opens the gate; anything else (absent, false,
  # "false", empty) keeps it shut — mirrors the layout's `== true` test.
  pdf_public = src_fm[/^pdf_public:\s*(\S+)\s*$/, 1].to_s.strip == "true"
  # Issue #305: every real entry's archive name obeys the field's own rule.
  # Decap applies it only to saves made in /admin; this catches a hand edit.
  # Committed pass only: the open-gate copy adds fixtures that break the rule
  # on purpose, and its real entries are the same files checked here.
  if !OPEN_PASS && !pdf_key.empty?
    check(failures, "_media/#{slug}.md pdf_archive_file #{pdf_key.inspect} ends in a lowercase .pdf (the field's rule)") do
      !field_suffix_rule.nil? && field_suffix_rule.match?(pdf_key)
    end
  end
  # Item 1 of the review round on issue #306: the PDF's bytes live in a private
  # archive CI cannot read, so whether the object EXISTS is the deploy's check
  # (it fails loudly). What CI can verify is the name: the deploy refuses any
  # opted-in name outside `[A-Za-z0-9._-]+.pdf`, and the admin field is looser,
  # so a ticked box over such a name would pass the editor and fail the deploy.
  # Committed pass only (the open-gate copy's fixtures break the rule on
  # purpose); it runs whatever the gate state, since it reads the source.
  if !OPEN_PASS && (front = media_front_matter(src)) && front["pdf_public"] == true
    opted_key = front["pdf_archive_file"].to_s.strip
    check(failures, "_media/#{slug}.md publishes its PDF under a name the deploy accepts (#{opted_key.inspect})") do
      deploy_accepts_pdf_key?(opted_key)
    end
    unless deploy_accepts_pdf_key?(opted_key)
      puts "       ^ _media/#{slug}.md has \"Publish this PDF\" ticked, but its archived file name"
      puts "         #{opted_key.inspect} cannot be published. The name must use only letters, numbers,"
      puts "         dots, dashes and underscores (no spaces, no slashes, no \"..\"), and end in a"
      puts "         lowercase .pdf. Rename the file in the private archive to match and update"
      puts "         the \"Archived PDF\" field, or untick \"Publish this PDF\"."
    end
  end
  page = read(MediaRules.page_path(SITE, src, media_front_matter(src)))
  next if page.nil?
  gated = page.include?("noindex,nofollow")
  if OPEN_PASS
    check(failures, "/media/#{slug}/ renders its full page, not the coming-soon shell") { !gated }
  end
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
      if pdf_public && pdf_key.match?(PDF_SUFFIX_RE)
        pdf_public_checks += 1
        href = "/media-pdfs/#{pdf_key}"
        check(failures, "/media/#{slug}/ links to its published PDF (#{href})") do
          page.include?(href)
        end
        # Issue #195, belt half: the gate is open, so the layout's has_pdf
        # guard let the button through — and the href it RENDERED (not just the
        # front-matter string) must still end in `.pdf`. This catches the guard
        # regressing even if the seam pattern still blocks new saves.
        check(failures, "/media/#{slug}/'s rendered PDF href ends in a lowercase .pdf") do
          h = page[PDF_HREF_RE, 1]
          !h.nil? && h.match?(PDF_SUFFIX_RE)
        end
        # Ticking the box renders a download button; if nothing put the file
        # under _site/media-pdfs/ the button is a confident 404. The publish
        # step that copies an opted-in object out of the private archive is
        # platform-side (cms-platform), so until a site's deploy runs it this
        # assertion is what stops the box being ticked into a broken link
        # rather than a working download.
        #
        # A name the deploy would refuse is not staged and is reported, with the
        # reason, by the committed pass's name check; failing "exists" for it
        # too would only say the same thing less usefully.
        if deploy_accepts_pdf_key?(pdf_key)
          check(failures, "published PDF #{href} exists in _site") do
            File.exist?(File.join(SITE, "media-pdfs", pdf_key))
          end
        end
      elsif pdf_public
        pdf_refused_checks += 1
        # Issue #305: the box is ticked but the name is not a lowercase `.pdf`.
        # The field rejects that name at save time and the deploy refuses to
        # copy it out of the archive, so the layout must not offer a download
        # either: a button here would link to a file that is never published.
        check(failures, "/media/#{slug}/ shows no PDF button for #{pdf_key.inspect} (not a lowercase .pdf name)") do
          !page.include?("/media-pdfs/") && page[PDF_HREF_RE, 1].nil?
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
  gate_hidden(failures, "the issue #194 outbound-link label checks")
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
# Two DIFFERENT reasons these can be zero, and saying the wrong one is worse
# than saying nothing: "no entry carries a key" is a content statement, and
# while the site gate is shut it is simply false — every media page is a
# coming-soon shell, so there is no rendered page for either assertion to read.
# Count the keys in the SOURCE, independently of the gate, so the note names the
# real reason.
keys_in_content = media_src.count { |f| read(f).to_s =~ /^pdf_archive_file:\s*\S/ }
if OPEN_PASS
  # The open-gate copy carries PDF_FIXTURES, so all three paths must run here;
  # a zero means the fixtures or the gate did not reach the built pages.
  check(failures, "PDF withhold assertion ran (#{pdf_gated_checks} entries)") { pdf_gated_checks.positive? }
  check(failures, "PDF publish assertion ran (#{pdf_public_checks} entries)") { pdf_public_checks.positive? }
  check(failures, "PDF suffix-rule assertion ran (#{pdf_refused_checks} entries)") { pdf_refused_checks.positive? }
elsif pdf_gated_checks.zero? && pdf_public_checks.zero? && pdf_refused_checks.zero?
  if keys_in_content.zero?
    puts "  note no media entry carries a `pdf_archive_file`, so NEITHER the withhold"
    puts "       assertion nor the publish assertion ran on this build. The open-gate"
    puts "       pass below runs both on synthetic entries."
  else
    puts "  note #{keys_in_content} media entr#{keys_in_content == 1 ? 'y carries' : 'ies carry'} a " \
         "`pdf_archive_file`, but site_live is false, so"
    puts "       every media page is a coming-soon shell and NEITHER the withhold nor"
    puts "       the publish assertion could run on this build. The open-gate pass"
    puts "       below runs both, adding synthetic entries for the publish half."
  end
else
  puts "  ok   PDF gate exercised: #{pdf_gated_checks} withheld, #{pdf_public_checks} published, " \
       "#{pdf_refused_checks} refused for their suffix"
  if pdf_public_checks.zero?
    puts "  note no entry has `pdf_public: true`, so the PUBLISH half did not run on this"
    puts "       build. The withhold half (the default, and the security-relevant one) did;"
    puts "       the open-gate pass below runs the publish half on a synthetic entry."
  end
end

# Repo-wide, and deliberately not scoped to _media: the invariant is that PDF
# BYTES never land in this PUBLIC repo at all, from any path — an editor upload,
# a hand-copied offprint, a well-meaning `assets/` commit. _site is excluded
# because a build legitimately materialises opted-in PDFs there; it is never
# committed (.gitignore).
# The skip list is matched against the path RELATIVE to the tree being scanned
# and as whole path segments: an absolute path would let a TMPDIR containing
# `/vendor/` or `/_site/` quietly skip the whole open-gate copy, and a bare
# substring would let `xgit` stand in for `.git`.
pdf_scan_skip = %w[_site .git .cms-platform node_modules vendor e2e].freeze
pdf_bytes_in_repo = Dir.glob(File.join(ROOT, "**", "*.pdf"), File::FNM_CASEFOLD)
                       .map { |f| File.expand_path(f) }
                       .reject do |f|
                         rel = f.delete_prefix("#{ROOT}/")
                         rel.split("/")[0...-1].any? { |seg| pdf_scan_skip.include?(seg) }
                       end
check(failures, "no PDF bytes are committed to this public repo") do
  pdf_bytes_in_repo.empty?
end
unless pdf_bytes_in_repo.empty?
  pdf_bytes_in_repo.first(5).each { |f| puts "       stray PDF: #{f}" }
end

puts
puts "== Fonts are self-hosted, not fetched from Google =="
# A visitor's browser asking fonts.googleapis.com / fonts.gstatic.com sends that
# visitor's IP to Google, which is a poor fit for a privacy lawyer's site and
# costs a render-blocking third-party round trip. The two families live in
# assets/fonts/ (sources and OFL licenses in SOURCES.txt) and are declared by
# @font-face in jodidaniel.css. The hostnames are a lexical token, so this is a
# plain scan of every built text file rather than a parse.
GOOGLE_FONT_HOST_RE = /fonts\.(?:googleapis|gstatic)\.com/i
built_text_files = Dir.glob(File.join(SITE, "**", "*.{html,css,js,svg,xml,json}"))
google_font_refs = built_text_files.select do |f|
  File.read(f, encoding: "utf-8", invalid: :replace, undef: :replace).match?(GOOGLE_FONT_HOST_RE)
end
check(failures, "no built page or asset references fonts.googleapis.com / fonts.gstatic.com (#{built_text_files.size} files scanned)") do
  !built_text_files.empty? && google_font_refs.empty?
end
google_font_refs.first(5).each { |f| puts "       Google Fonts reference: #{f.delete_prefix("#{SITE}/")}" }

site_css = read(File.join(SITE, "assets", "css", "jodidaniel.css"))
font_faces = site_css.to_s.scan(/@font-face\s*\{[^}]*\}/m)
check(failures, "jodidaniel.css declares @font-face rules for Raleway and Source Sans Pro") do
  font_faces.any? { |b| b.include?("'Raleway'") } && font_faces.any? { |b| b.include?("'Source Sans Pro'") }
end
check(failures, "every @font-face sets font-display: swap (no invisible text while it loads)") do
  !font_faces.empty? && font_faces.all? { |b| b.match?(/font-display:\s*swap\b/) }
end
WOFF2_MAGIC = "wOF2".b
font_urls = font_faces.flat_map { |b| b.scan(/url\(\s*['"]?([^'")\s]+)['"]?\s*\)/).flatten }
check(failures, "every @font-face url() is a same-site woff2 file that exists and starts with the woff2 magic") do
  !font_urls.empty? && font_urls.all? do |u|
    path = File.expand_path(u, File.join(SITE, "assets", "css"))
    !u.match?(%r{\A[a-z]+:|\A//}i) && path.start_with?("#{SITE}/") && path.end_with?(".woff2") &&
      File.file?(path) && File.binread(path, 4) == WOFF2_MAGIC
  end
end
check(failures, "assets/fonts/ ships an OFL license file for each family beside the fonts") do
  %w[OFL-Raleway.txt OFL-SourceSansPro.txt SOURCES.txt].all? do |n|
    File.file?(File.join(SITE, "assets", "fonts", n))
  end
end
# The critical files are preloaded on both layouts so the first paint does not
# wait for the stylesheet to discover them; `crossorigin` is required on a font
# preload or the browser fetches the file twice.
font_preload_pages = ["index.html"] + Dir.glob(File.join(SITE, "media", "*", "index.html")).sort.first(1).map { |f| f.delete_prefix("#{SITE}/") }
font_preload_pages.each do |page|
  html = read(File.join(SITE, page))
  preloads = html.to_s.scan(/<link\b[^>]*>/m).select { |t| t.match?(/\brel="preload"/) }
  hrefs = preloads.map { |t| t[/\bhref="([^"]+)"/, 1] }.compact
  check(failures, "#{page} preloads 1-2 self-hosted woff2 files, each with crossorigin, each present in the build") do
    (1..2).cover?(hrefs.size) && preloads.all? { |t| t.match?(/\bcrossorigin\b/) && t.match?(/\bas="font"/) } &&
      hrefs.all? { |h| h.end_with?(".woff2") && File.file?(File.join(SITE, h)) }
  end
end

puts
puts "== Internal engineering notes are not served =="
# Jekyll COPIES anything it is not told to exclude, so a maintainer file added
# at the repo root or in a new directory is published by default — the failure
# is silent, and it is a leak of the wrong kind of detail (CONTENT-MODEL.md and
# AGENTS.md both describe the private media archive and how its gate works).
# Both were measured serving 200 from prod before `_config.yml` excluded them.
# Assert on the BUILT tree rather than on the exclude list: the invariant is
# "not published", and a future rename would leave an exclude-list check green
# while the file went back to being served.
INTERNAL_DOCS = %w[AGENTS.md CLAUDE.md README.md docs].freeze
INTERNAL_DOCS.each do |name|
  check(failures, "#{name} is NOT published to _site") do
    !File.exist?(File.join(SITE, name))
  end
end
# The catch-all: any OTHER markdown at the built root is almost certainly a
# maintainer note that slipped in. `.md` under _media/ etc. is rendered to HTML,
# so a surviving .md file here is a static copy, never a page.
stray_md = Dir.glob(File.join(SITE, "*.md")).map { |f| File.basename(f) }
check(failures, "no stray markdown is published at the site root") { stray_md.empty? }
stray_md.first(5).each { |f| puts "       stray markdown: /#{f}" }

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
home_layout_src = read(File.join(ROOT, "_layouts", "home.html"))
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
media_layout_src = read(File.join(ROOT, "_layouts", "media.html"))
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
  settings_yaml_for_media = YAML.safe_load(read(File.join(ROOT, "_data", "settings.yml")) || "") || {}
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
  gate_hidden(failures, "the authored-vs-coverage heading/ordering checks")
end

puts "== Upcoming Events (Jodi 2026-08-30 feedback) =="
# _events/ is a NEW folder collection (feedback item 3), ordered by
# `start_date` rather than `weight` like every sibling collection above --
# see the comment on `events:` in _config.yml. Front matter is parsed with
# the `yaml` stdlib (AGENTS.md), never a regex/line-scan.
events_src = Dir[File.join(ROOT, "_events", "*.md")].sort
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
  gate_hidden(failures, "the built-page event title/date_display/order checks")
end

puts "== Above the fold: blurb + nav (Jodi 2026-08-30 feedback) =="
# Feedback item 2: the one-sentence `lead` and the nav pills both have to
# land inside the first viewport; the full bio moves below them. The pixel
# measurement itself isn't reproducible in pure Ruby (that's what
# measure-fold.js is for -- see docs/CONTENT-MODEL.md) but the DOM ordering
# that makes it *possible* is, and that's what a careless future edit -- one
# that moves .intro-bio back above the nav, say -- would silently undo with
# no build error. This checks that ordering, not the pixels.
about_yaml_for_lead = YAML.safe_load(read(File.join(ROOT, "_data", "about.yml")) || "") || {}
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
  gate_hidden(failures, "the intro-lead/intro-nav/intro-bio ordering check")
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
  gate_hidden(failures, "the admin-seam <-> layout section-id cross-check")
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

puts "== editor-facing admin copy stays out of developer vocabulary =="
# Every word an editor reads in /admin comes from this seam, and the premise of
# this site (AGENTS.md, "Keep every visible string /admin-editable") is that its
# owner maintains it with no developer standing by. Copy that names an internal
# key (`site_live`), states a code comparison (`= false`), or reaches for
# developer vocabulary ("gating", "boolean") tells her nothing she can act on --
# and nothing else fails when it drifts back, because Decap renders whatever
# string it is handed. Both assertions below were RED on the seam as it stood --
# "Site Live (controls gating)" and "Settings & Gating" on the vocabulary one,
# "Coming Soon (shown when site_live = false)" and its footer sibling on both.
#
# Scope is deliberately narrow, so this stays a lint and not a style opinion: an
# internal key is a snake_case token (never natural English), and the vocabulary
# list holds only words that carry no meaning for a non-technical owner. Plain
# words she already meets in Decap's own chrome are NOT on it.
editor_copy = []
collect_copy = lambda do |node|
  case node
  when Hash
    node.each do |k, v|
      editor_copy << [k, v] if %w[label hint].include?(k) && v.is_a?(String)
      # `pattern: ["<regex>", "<message shown on a bad value>"]` -- element 1 is
      # editor-facing copy too, and parsing (rather than scanning lines) is what
      # lets this tell it apart from the regex sitting beside it.
      editor_copy << ["pattern message", v[1]] if k == "pattern" && v.is_a?(Array) && v[1].is_a?(String)
      collect_copy.call(v)
    end
  when Array
    node.each { |v| collect_copy.call(v) }
  end
end
collect_copy.call(seam_yaml)
# The site's `$ref` leaves shared PDF labels and hints out of the source seam.
# Include the three resolved fields from the rendered config so centralized
# platform copy stays under the same editor-language guard.
%w[pdf_archive_file pdf_public pdf_label].each do |name|
  collect_copy.call(media_admin_fields[name])
end

# Guard the denominator: an empty or mis-parsed seam would make both checks
# below pass over nothing at all.
check(failures, "admin seam yields editor-facing copy to check (#{editor_copy.size} strings)") do
  editor_copy.size > 50
end

internal_key = /\b[a-z]+(?:_[a-z]+)+\b|=\s*(?:true|false)\b/
key_offenders = editor_copy.select { |(_, text)| text =~ internal_key }
check(failures, "no admin label/hint/validation message names an internal key or a code comparison") do
  key_offenders.empty?
end
key_offenders.each { |(kind, text)| puts "       ^ #{kind}: #{text}" }

jargon = /\b(?:gating|gated|boolean|front[- ]matter|yaml|repo|repository|commit|permalink|slug|widget|true|false|null|nil)\b/i
jargon_offenders = editor_copy.select { |(_, text)| text =~ jargon }
check(failures, "no admin label/hint/validation message uses developer vocabulary") do
  jargon_offenders.empty?
end
jargon_offenders.each { |(kind, text)| puts "       ^ #{kind}: #{text}" }

if OPEN_PASS
  puts
  puts "#{STATS[:executed]} assertion(s) executed on the open-gate build."
  if failures.empty?
    puts "All open-gate assertions passed."
    exit 0
  end
  puts "#{failures.size} open-gate assertion(s) FAILED:"
  failures.each { |f| puts "  - #{f}" }
  exit 1
end

committed_executed = STATS[:executed]
puts
puts "#{committed_executed} assertion(s) executed on the committed-gate build."

# ---------------------------------------------------------------------------
# The open-gate pass (issue #306). See the header comment for the design.
# ---------------------------------------------------------------------------

# What goes into the disposable copy is an ALLOWLIST, never "everything except":
# the files `git ls-files` reports, nothing else. A checkout carries local-only
# content git ignores (the OAuth proxy's real credentials in
# infrastructure/site-params.env, .cms-platform, .jodidaniel-real-content,
# e2e/node_modules), and an exclude list would copy whatever it forgot to name
# into /tmp. Without git metadata (a tarball checkout) there is no list to ask,
# so the fallback walks the tree and refuses the local-only names below.
#
# Build output and caches, installed gems (Bundler still resolves them from
# REPO_ROOT, where the build is launched), local agent state and `.git` are
# never copied either, so the copy is not a repository and nothing run in it can
# reach `origin`.
OPEN_COPY_SKIP = %w[.git _site .jekyll-cache .sass-cache .bundle vendor node_modules .claude].freeze
# Fallback only: names and shapes that hold local-only or credential content.
OPEN_COPY_LOCAL_ONLY = %w[infrastructure .cms-platform .jodidaniel-real-content e2e].freeze

# Paths, relative to REPO_ROOT, to copy: nil when there is no usable git
# metadata. Argument array and NUL-delimited output, so no shell string and no
# name can be misread.
def tracked_paths
  return nil unless File.exist?(File.join(REPO_ROOT, ".git"))

  out = IO.popen(["git", "-C", REPO_ROOT, "ls-files", "-z"], err: File::NULL, &:read)
  return nil unless $?.success?

  out.force_encoding("UTF-8").split("\0").reject(&:empty?)
rescue SystemCallError
  nil
end

def walked_paths
  Dir.glob("**/*", File::FNM_DOTMATCH, base: REPO_ROOT).select do |rel|
    segs = rel.split("/")
    base = segs.last
    next false if base == "." || segs.include?("..")
    next false if segs.any? { |seg| OPEN_COPY_SKIP.include?(seg) || OPEN_COPY_LOCAL_ONLY.include?(seg) }
    next false if base.start_with?(".env") || base.end_with?(".env")

    File.file?(File.join(REPO_ROOT, rel)) || File.symlink?(File.join(REPO_ROOT, rel))
  end
end

# Copy the source tree into `tmp`. Returns the relative paths copied and the
# listing mode, for the assertion that the copy holds nothing else.
def copy_source_tree(tmp)
  tracked = tracked_paths
  paths = tracked || walked_paths
  paths.each do |rel|
    next if OPEN_COPY_SKIP.include?(rel.split("/").first)

    src = File.join(REPO_ROOT, rel)
    next unless File.file?(src) # a tracked file deleted in the working tree, or a submodule

    dest = File.join(tmp, rel)
    FileUtils.mkdir_p(File.dirname(dest))
    FileUtils.cp(src, dest)
  end
  [paths, tracked ? :git : :walk]
end

def write_pdf_fixtures(media_dir)
  PDF_FIXTURES.each do |slug, key, pdf_public|
    front_matter = {
      "category" => "Press Coverage",
      "title" => "Verifier fixture #{slug.delete_prefix(PDF_FIXTURE_PREFIX)}",
      "source" => "Synthetic entry",
      "date_display" => "October 2026",
      "article_url" => "https://example.com/#{slug}",
      "pdf_archive_file" => key,
      "pdf_public" => pdf_public,
      "weight" => 999,
    }
    File.write(File.join(media_dir, "#{slug}.md"), "#{YAML.dump(front_matter)}---\n", encoding: "utf-8")
  end
end

# Stand in for the deploy's publish-opted-in-pdfs.sh, which copies an opted-in
# object out of the private archive to exactly this path. EVERY `pdf_public:
# true` entry in the copy's `_media` gets a file -- the real ones as well as the
# fixtures -- provided the deploy would accept its name (DEPLOY_PDF_KEY_RE, no
# `..`). CI cannot read the private archive, so whether the object exists is the
# deploy's check, which fails loudly; staging here keeps a legitimately ticked
# real entry from turning the required check red for a file only the deploy can
# see. A name the deploy would refuse gets nothing, and the committed pass's
# name check reports it.
def stage_published_pdfs(media_dir, site)
  dir = File.join(site, "media-pdfs")
  FileUtils.mkdir_p(dir)
  Dir.glob(File.join(media_dir, "*.md")).sort.each do |entry|
    front = media_front_matter(entry)
    next unless front && front["pdf_public"] == true

    key = front["pdf_archive_file"].to_s.strip
    next unless deploy_accepts_pdf_key?(key)

    File.write(File.join(dir, key), "verifier stand-in, not a real PDF\n")
  end
end

puts
puts "== open-gate pass: the same assertions on a disposable build with site_live forced on =="
settings_path = File.join(REPO_ROOT, "_data", "settings.yml")
settings_before = File.binread(settings_path)
open_built = false
open_passed = false
copied_paths = []
copy_mode = nil
stray_in_copy = []
Dir.mktmpdir("verify-open-gate-") do |tmp|
  copied_paths, copy_mode = copy_source_tree(tmp)
  # Prove the allowlist held, from what is actually on disk: every file in the
  # copy must be one that was meant to go in (before the fixtures, settings edit
  # and build add their own).
  on_disk = Dir.glob("**/*", File::FNM_DOTMATCH, base: tmp).select { |rel| File.file?(File.join(tmp, rel)) }
  stray_in_copy = on_disk - copied_paths
  if copy_mode == :walk
    stray_in_copy += on_disk.select do |rel|
      rel.split("/").first == "infrastructure" || File.basename(rel).end_with?(".env")
    end
  end

  copy_settings = File.join(tmp, "_data", "settings.yml")
  settings = YAML.safe_load(File.read(copy_settings, encoding: "utf-8")) || {}
  settings["site_live"] = true
  File.write(copy_settings, YAML.dump(settings), encoding: "utf-8")

  write_pdf_fixtures(File.join(tmp, "_media"))

  site = File.join(tmp, "_site")
  $stdout.flush
  # JEKYLL_ENV=production, as the deploy builds it: the open-gate build stands
  # in for what launch would ship.
  open_built = system({ "JEKYLL_ENV" => "production" },
                      "bundle", "exec", "jekyll", "build", "--quiet", "--source", tmp, "--destination", site,
                      chdir: REPO_ROOT)
  if open_built
    stage_published_pdfs(File.join(tmp, "_media"), site)
    $stdout.flush
    open_passed = system(RbConfig.ruby, File.expand_path(__FILE__), "--open-pass", tmp, site)
  end
end
puts
puts "#### back in the committed-gate pass"
check(failures, "open-gate copy holds only tracked source files (#{copy_mode == :git ? 'git ls-files' : 'no git metadata, so a walk without infrastructure/ or *.env'}; #{copied_paths.size} paths), no local-only content") do
  stray_in_copy.empty?
end
stray_in_copy.first(5).each { |f| puts "       unexpected in the copy: #{f}" }
check(failures, "open-gate build succeeds (bundle exec jekyll build on the disposable copy)") { open_built }
check(failures, "open-gate pass: every assertion passed (its output is above)") { open_passed } if open_built
check(failures, "_data/settings.yml is unchanged by the open-gate pass (the committed site_live stays as is)") do
  File.binread(settings_path) == settings_before
end

puts
if failures.empty?
  puts "All build-artifact assertions passed (committed-gate build and open-gate build)."
  exit 0
else
  puts "#{failures.size} assertion(s) FAILED:"
  failures.each { |f| puts "  - #{f}" }
  exit 1
end
