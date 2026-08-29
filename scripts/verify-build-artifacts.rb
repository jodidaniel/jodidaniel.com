#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

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

pdf_field = media_seam_fields["pdf"]
check(failures, "admin seam's `pdf` field offers a file upload") do
  pdf_field && pdf_field["widget"] == "file"
end
check(failures, "admin seam's `pdf` field validates a `.pdf` suffix (issue #195)") do
  pattern = pdf_field && pdf_field["pattern"]
  pattern.is_a?(Array) && pattern.length == 2 && pattern[0].is_a?(String) &&
    pattern[0].include?(".pdf$") && !pattern[1].to_s.empty?
end

check(failures, "admin seam offers `link_label` on media entries, and it's optional (issue #194)") do
  f = media_seam_fields["link_label"]
  !f.nil? && f["required"] == false
end
check(failures, "admin seam offers `pdf_label` on media entries, and it's optional (issue #194)") do
  f = media_seam_fields["pdf_label"]
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
pdf_checks = 0
article_labels = {} # slug => rendered label text, ungated pages only
media_src.each do |src|
  slug = File.basename(src, ".md")
  page = read(File.join(SITE, "media", slug, "index.html"))
  next if page.nil?
  gated = page.include?("noindex,nofollow")
  src_fm = read(src)
  article = src_fm[/^article_url:\s*"?([^"\n]+)"?/, 1].to_s.strip
  pdf = src_fm[/^pdf:\s*"?([^"\n]+)"?/, 1].to_s.strip
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
    unless pdf.empty?
      pdf_checks += 1
      check(failures, "/media/#{slug}/ links to its PDF (#{pdf})") { page.include?(pdf) }
      check(failures, "PDF #{pdf} is published to _site") do
        File.exist?(File.join(SITE, pdf.sub(%r{\A/}, "")))
      end
      # Issue #195, belt half: the entry's front matter carries a `pdf:`, so
      # the layout's has_pdf guard should have let the button through — and
      # the href it rendered (not just the front-matter string) must still
      # end in `.pdf`. This is what would catch the guard regressing (e.g.
      # someone loosening the suffix check) even if the seam pattern above
      # still blocks new saves.
      check(failures, "/media/#{slug}/'s rendered PDF href ends in .pdf") do
        href = page[PDF_HREF_RE, 1]
        !href.nil? && href.downcase.end_with?(".pdf")
      end
    end
  end
end

# Issue #194 regression guard: before the fix, EVERY item said "Read the
# article" regardless of category — a podcast, a Supreme Court brief PDF, and
# a conference talk all rendered the same wrong verb. Assert the category
# default actually reached the built HTML, not just the layout source: at
# least one non-default label must appear, and (since the catalogue carries
# at least one `Podcasts & Interviews` and one `Policy & Advocacy` entry —
# see _media/1-ai-health-care-hipaa.md and _media/1-fda-amicus.md) at least
# two DISTINCT labels must appear across the built, ungated pages.
distinct_labels = article_labels.values.compact.uniq
check(failures, "built media pages render more than one outbound-link label (issue #194)") do
  !article_labels.empty? && distinct_labels.length >= 2
end
check(failures, "built media pages do NOT all say \"Read the article\" (issue #194)") do
  !article_labels.empty? && distinct_labels != ["Read the article"]
end

# The two PDF assertions above are CONDITIONAL — they fire only for an entry
# that actually carries a `pdf:`, and only while the gate is open. With none
# (the state today: the widget shipped before any editor used it) they are
# vacuous, and "All build-artifact assertions passed" would imply a coverage
# this script did not have. That is the failure mode AGENTS.md names as a green
# light wired to nothing, so say it out loud instead. Not a failure: an empty
# PDF set is a legitimate content state, and the first real upload arms them.
if pdf_checks.zero?
  puts "  note no media entry carries a `pdf:` yet, so the PDF link/publish assertions"
  puts "       did NOT run. A pass here is not evidence the PDF chain works — see"
  puts "       docs/CONTENT-MODEL.md for the build probe that verified it, and how"
  puts "       to re-run it."
else
  puts "  ok   PDF assertions exercised on #{pdf_checks} media entr#{pdf_checks == 1 ? 'y' : 'ies'}"
end

puts
if failures.empty?
  puts "All build-artifact assertions passed."
  exit 0
else
  puts "#{failures.size} assertion(s) FAILED:"
  failures.each { |f| puts "  - #{f}" }
  exit 1
end
