# frozen_string_literal: true

# Reads the site title, the launch page title and the launch search-result
# description from `_data/settings.yml` (`seo:`), so the owner edits them in
# /admin (Site Settings) instead of in `_config.yml` / `index.html`, which only
# a commit can change.
#
# WHY A PLUGIN. {% seo %} (jekyll-seo-tag) composes the tab title, meta
# description, Open Graph and structured data from `site.title`,
# `site.description` and `page.title`, and nothing in Liquid can hand it
# different values. Rather than replace {% seo %} (which would change HOW the
# share tags are composed), this changes only WHERE the three values come from:
# it overwrites those config/page values right after the site is read and
# before any generator or renderer runs, so the output of {% seo %}, the feed
# and the gated <title> in _layouts/home.html / media.html are exactly what the
# literal values produced.
#
# A blank or missing field leaves the value alone: `title:` in _config.yml stays
# as the fallback site title; with no launch title the page serves the site
# title alone, and with no launch description it serves none.
#
# Unit tests: scripts/test-site-meta.rb

module JodiSiteMeta
  # Pure data shaping, kept Jekyll-free so the unit tests need no site build.
  # Returns only the keys that have a non-blank string, so the caller never
  # overwrites a value with nothing.
  def self.overrides(settings)
    seo = settings.is_a?(Hash) ? settings["seo"] : nil
    return {} unless seo.is_a?(Hash)

    {
      "site_title" => seo["site_title"],
      "launch_title" => seo["launch_title"],
      "launch_description" => seo["launch_description"]
    }.select { |_, value| value.is_a?(String) && !value.strip.empty? }
  end

  def self.apply(config, home_pages, settings)
    found = overrides(settings)
    config["title"] = found["site_title"] if found.key?("site_title")
    config["description"] = found["launch_description"] if found.key?("launch_description")
    home_pages.each { |page| page.data["title"] = found["launch_title"] } if found.key?("launch_title")
    found
  end
end

Jekyll::Hooks.register :site, :post_read do |site|
  home_pages = site.pages.select { |page| page.data["layout"] == "home" }
  JodiSiteMeta.apply(site.config, home_pages, site.data["settings"])
end
