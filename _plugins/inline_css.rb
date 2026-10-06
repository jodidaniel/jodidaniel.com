# frozen_string_literal: true

# {% inline_css '/assets/css/jodidaniel.css' %} -- the readable stylesheet,
# minified at build time, for a layout to put in a <style> element.
#
# WHY. jodidaniel.css was the only render-blocking request on the home and
# media pages: a 26.8 KB file (54% of it comments) that the browser had to
# fetch, after the HTML, before it could paint anything. Inlined and minified
# it rides in the HTML response, and the first paint no longer waits on a
# second round trip. Measured on an emulated slow-4G / slow-3G phone, first
# contentful paint went from 648 / 1,488 ms to about 400 / 700 ms.
#
# The source stays the file people edit (assets/css/jodidaniel.css, also still
# published for the 404 page, which links it). Nothing is checked in
# pre-minified, so the two cannot drift.
#
# MINIFIER. dart-sass in compressed mode, through the `sass-embedded` gem that
# jekyll-sass-converter (a Jekyll dependency) already loads: no new dependency.
# The stylesheet is plain CSS, which Sass accepts as is.
#
# FONT URLS. The stylesheet says `url('../fonts/x.woff2')`, which is relative
# to /assets/css/. Inlined into a page at /media/<slug>/ that would resolve to
# the wrong place, so each is rewritten to a root-relative /assets/fonts/ URL
# (with `baseurl`, if the site sets one).
#
# Unit tests: scripts/test-inline-css.rb. Build proof: scripts/verify-build-artifacts.rb.

module JodiInlineCss
  CACHE = {}
  FONT_URL_RE = %r{url\((["']?)\.\./fonts/}

  # Pure text shaping, kept free of Jekyll and Sass so the unit tests need
  # neither. Raises rather than return CSS that would end the <style> element
  # early (a build that ships that is worse than a build that fails).
  def self.rewrite_font_urls(css, baseurl)
    prefix = "#{baseurl.to_s.chomp("/")}/assets/fonts/"
    css.gsub(FONT_URL_RE) { "url(#{Regexp.last_match(1)}#{prefix}" }
  end

  def self.safe_for_style_element!(css)
    raise ArgumentError, "inline_css: CSS contains </style" if css.match?(%r{</style}i)

    css
  end

  # `minifier` is any callable String -> String; the tag passes dart-sass.
  def self.render(css, baseurl, minifier)
    safe_for_style_element!(rewrite_font_urls(minifier.call(css), baseurl).strip)
  end

  def self.sass_minifier
    require "sass-embedded"
    # charset: false -- no @charset rule or BOM, which has no place inside <style>.
    ->(css) { Sass.compile_string(css, style: :compressed, charset: false).css }
  end
end

if defined?(Liquid::Tag)
  class JodiInlineCssTag < Liquid::Tag
    def initialize(tag_name, markup, options)
      super
      @path = markup.strip.delete_prefix("'").delete_prefix('"').delete_suffix("'").delete_suffix('"')
      raise Liquid::SyntaxError, "inline_css: give a path, e.g. {% inline_css '/assets/css/jodidaniel.css' %}" if @path.empty?
    end

    def render(context)
      site = context.registers[:site]
      file = File.expand_path(@path.delete_prefix("/"), site.source)
      raise Errno::ENOENT, "inline_css: #{@path} is not in the site source" unless file.start_with?("#{File.expand_path(site.source)}/") && File.file?(file)

      # Keyed by mtime and baseurl too, so `jekyll serve` picks up an edit.
      key = [file, File.mtime(file), site.config["baseurl"]]
      JodiInlineCss::CACHE[key] ||= JodiInlineCss.render(File.read(file, encoding: "utf-8"), site.config["baseurl"], JodiInlineCss.sass_minifier)
    end
  end

  Liquid::Template.register_tag("inline_css", JodiInlineCssTag)
end
