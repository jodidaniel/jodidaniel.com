#!/usr/bin/env ruby
# frozen_string_literal: true

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
  File.exist?(path) ? File.read(path) : nil
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

puts
if failures.empty?
  puts "All build-artifact assertions passed."
  exit 0
else
  puts "#{failures.size} assertion(s) FAILED:"
  failures.each { |f| puts "  - #{f}" }
  exit 1
end
