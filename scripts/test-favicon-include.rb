#!/usr/bin/env ruby
# frozen_string_literal: true

# Unit tests for _includes/favicon.html, which shadows the cms-platform theme's
# include. The theme's contract that `cms.favicon_url` is honored verbatim must
# survive the shadowing (_layouts/home.html and media.html tell editors to set it).
# No build, no network:
#
#   ruby scripts/test-favicon-include.rb

require "minitest/autorun"

# Liquid ships with Jekyll, so it is a bundle gem, not a system one: plain `ruby`
# (how site-verify runs this, through verify-build-artifacts.rb) may not see it.
# Fall back to the repo's bundle when it is missing.
begin
  require "liquid"
rescue LoadError
  ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
  require "bundler/setup"
  require "liquid"
end

class FaviconIncludeTest < Minitest::Test
  SOURCE = File.read(File.expand_path("../_includes/favicon.html", __dir__), encoding: "UTF-8")

  # Jekyll's relative_url with an empty baseurl is the identity on these paths.
  module Filters
    def relative_url(input) = input
  end

  def render(cms)
    Liquid::Template.parse(SOURCE).render({ "site" => { "cms" => cms } }, filters: [Filters])
  end

  def icon_links(html)
    html.scan(/<link rel="icon"[^>]*>/)
  end

  def test_default_links_favicon_ico_and_the_svg
    links = icon_links(render({}))
    assert_equal 2, links.size, links.inspect
    assert_includes links.join, 'href="/favicon.ico"'
    assert_includes links.join, 'href="/assets/favicon.svg"'
  end

  def test_default_links_the_apple_touch_icon
    assert_includes render({}), '<link rel="apple-touch-icon" href="/apple-touch-icon.png">'
  end

  def test_cms_favicon_url_is_honored_verbatim_as_the_only_icon
    html = render({ "favicon_url" => "https://example.com/brand.png" })
    assert_equal ['<link rel="icon" href="https://example.com/brand.png">'], icon_links(html)
    refute_includes html, "/favicon.ico"
    refute_includes html, "/assets/favicon.svg"
  end

  def test_cms_favicon_url_still_links_the_apple_touch_icon
    html = render({ "favicon_url" => "https://example.com/brand.png" })
    assert_includes html, 'rel="apple-touch-icon"'
  end
end
