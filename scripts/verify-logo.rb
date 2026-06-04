#!/usr/bin/env ruby
# frozen_string_literal: true

# Lightweight build-artifact assertion for issue #31 (jodidaniel's own logo,
# no leaked "AD" mark). jodidaniel.com ships no in-repo JS/Playwright harness
# (the gem's e2e suite is checked out at CI time and excluded from the build),
# so this is a self-contained pure-Ruby check — no toolchain beyond the Ruby
# already required to build the site.
#
#   bundle exec jekyll build
#   ruby scripts/verify-logo.rb
#
# TDD-shaped: FAILS on a build of plain `main` (the gem's "AD" logo.svg leaks
# through because jodidaniel ships none) and PASSES once the site's own JD mark
# is present. `scripts/` is excluded from the Jekyll build, so this file is
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

puts "== #31 Jodi's logo (no 'AD' leak) =="
logo = read(File.join(SITE, "assets", "images", "logo.svg"))
check(failures, "_site/assets/images/logo.svg exists (site file shadows the gem default)") { !logo.nil? }
check(failures, "logo is Jodi's 'JD' mark") { logo&.include?(">JD<") }
check(failures, "logo is NOT the gem's 'AD' (Adam Daniel) mark") { logo && !logo.include?(">AD<") }

# The rendered Decap admin config must resolve CMS_LOGO_URL to the site's own
# asset (the gem hook defaults logo_url to <url>/assets/images/logo.svg when
# cms.logo_url is unset, which the shadowing site file then serves).
admin_cfg = read(File.join(SITE, "admin", "config.yml"))
check(failures, "admin config.yml logo_url -> <site>/assets/images/logo.svg") do
  admin_cfg&.include?("logo_url: https://jodidaniel.com/assets/images/logo.svg")
end

puts
if failures.empty?
  puts "All logo assertions passed."
  exit 0
else
  puts "#{failures.size} assertion(s) FAILED:"
  failures.each { |f| puts "  - #{f}" }
  exit 1
end
