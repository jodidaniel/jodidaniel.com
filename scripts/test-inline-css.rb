#!/usr/bin/env ruby
# frozen_string_literal: true

# Regression tests for _plugins/inline_css.rb, which minifies assets/css/
# jodidaniel.css at build time for the layouts to inline. No Jekyll build, no
# network:
#
#   ruby scripts/test-inline-css.rb
#
# The minifier itself (dart-sass) is stubbed: it is a bundle gem, so plain
# `ruby` on a CI runner cannot load it. scripts/verify-build-artifacts.rb proves
# the real thing on the built site (minified, inlined, no stylesheet link left).

require "minitest/autorun"
require "fileutils"
require "tmpdir"

# Liquid is a Jekyll dependency, so on a CI runner it exists only in the bundle
# while minitest is a system gem: put the bundle on the load path from this
# repo's Gemfile if `ruby` alone cannot see it (see test-site-meta.rb).
begin
  require "liquid"
rescue LoadError
  ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
  require "bundler/setup"
  require "liquid"
end

ROOT = File.expand_path("..", __dir__)
require File.join(ROOT, "_plugins", "inline_css.rb")

class InlineCssTest < Minitest::Test
  Site = Struct.new(:source, :config)

  def squash(css) = css.gsub(%r{/\*.*?\*/}m, "").gsub(/\s+/, "")

  def test_font_urls_become_root_relative_for_every_quote_style
    css = "a{src:url('../fonts/a.woff2')}b{src:url(\"../fonts/b.woff2\")}c{src:url(../fonts/c.woff2)}"
    out = JodiInlineCss.rewrite_font_urls(css, "")
    assert_equal "a{src:url('/assets/fonts/a.woff2')}b{src:url(\"/assets/fonts/b.woff2\")}c{src:url(/assets/fonts/c.woff2)}", out
  end

  def test_font_urls_carry_the_baseurl
    assert_includes JodiInlineCss.rewrite_font_urls("a{src:url(\"../fonts/a.woff2\")}", "/jodi/"), 'url("/jodi/assets/fonts/a.woff2")'
  end

  def test_other_urls_are_left_alone
    css = "a{background:url(\"data:image/svg+xml,%3Csvg%3E\")}b{background:url(/x/../fonts.png)}"
    assert_equal css, JodiInlineCss.rewrite_font_urls(css, "")
  end

  def test_the_real_stylesheet_only_references_fonts_the_rewrite_covers
    css = File.read(File.join(ROOT, "assets", "css", "jodidaniel.css"), encoding: "utf-8")
    urls = css.scan(/url\(\s*["']?([^"')\s]+\.woff2)/).flatten
    refute_empty urls
    assert(urls.all? { |u| u.start_with?("../fonts/") }, "a woff2 url outside ../fonts/ would break once inlined: #{urls.inspect}")
    assert_empty JodiInlineCss.rewrite_font_urls(css, "").scan(/url\(\s*["']?\.\.\/fonts/)
  end

  def test_render_minifies_then_rewrites_and_strips
    out = JodiInlineCss.render("a { src: url('../fonts/a.woff2'); }", "", ->(css) { "\n#{squash(css)}\n" })
    assert_equal "a{src:url('/assets/fonts/a.woff2');}", out
  end

  def test_render_refuses_css_that_would_close_the_style_element
    assert_raises(ArgumentError) { JodiInlineCss.render("a{}", "", ->(_) { "a{content:'</STYLE><script>'}" }) }
  end

  def with_site(css = "a { color: red; }")
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "assets", "css"))
      File.write(File.join(dir, "assets", "css", "x.css"), css)
      File.write(File.join(dir, "outside.css"), "b{}")
      yield Site.new(File.join(dir, "site"), { "baseurl" => "" }), dir
    end
  end

  def render_tag(markup, site)
    JodiInlineCss::CACHE.clear
    template = Liquid::Template.parse("{% inline_css #{markup} %}")
    template.render!({}, registers: { site: site })
  end

  def test_tag_inlines_the_minified_file
    with_site("/* gone */ a { src: url('../fonts/a.woff2'); }") do |_, dir|
      site = Site.new(dir, { "baseurl" => "" })
      stub_minifier(->(css) { squash(css) }) do
        assert_equal "a{src:url('/assets/fonts/a.woff2');}", render_tag("'/assets/css/x.css'", site)
      end
    end
  end

  def test_tag_refuses_a_path_outside_the_site_source
    with_site do |_, dir|
      site = Site.new(File.join(dir, "assets"), { "baseurl" => "" })
      stub_minifier(->(css) { css }) do
        assert_raises(Errno::ENOENT) { render_tag("'/../outside.css'", site) }
        assert_raises(Errno::ENOENT) { render_tag("'/css/missing.css'", site) }
      end
    end
  end

  def test_tag_without_a_path_is_a_syntax_error
    assert_raises(Liquid::SyntaxError) { Liquid::Template.parse("{% inline_css %}") }
  end

  def stub_minifier(callable)
    original = JodiInlineCss.method(:sass_minifier)
    JodiInlineCss.define_singleton_method(:sass_minifier) { callable }
    yield
  ensure
    JodiInlineCss.define_singleton_method(:sass_minifier, original)
  end
end
