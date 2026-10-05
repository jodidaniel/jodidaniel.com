#!/usr/bin/env ruby
# frozen_string_literal: true

# Regression tests for scripts/media_rules.rb, the rules scripts/verify-build-artifacts.rb
# applies to `_media/*.md` entries (issues #338, #339). No build, no network:
#
#   ruby scripts/test-media-rules.rb
#
# If Jekyll is installed the slug tests also compare against Jekyll's own slugify, so a
# Jekyll upgrade that changes `:slug` fails here rather than as a mystery 404 on a PR.

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "media_rules"

class MediaRulesTest < Minitest::Test
  EM_DASH_FILE = "/repo/_media/99-zz-test-—-delete-me.md"

  # --- #338: a blank optional field is an absent key ------------------------------------

  def test_missing_optional_fields_read_as_empty
    fm = { "category" => "Press Coverage", "title" => "T", "weight" => 99 }
    %w[date_display link_label pdf_archive_file pdf_label].each do |key|
      assert_equal "", MediaRules.optional_text(fm, key), "#{key} absent should read as empty"
    end
  end

  def test_present_optional_fields_keep_their_value
    fm = { "date_display" => "April 2025", "pdf_label" => nil, "link_label" => "" }
    assert_equal "April 2025", MediaRules.optional_text(fm, "date_display")
    assert_equal "", MediaRules.optional_text(fm, "pdf_label")
    assert_equal "", MediaRules.optional_text(fm, "link_label")
  end

  def test_front_matter_without_date_display_passes_the_date_rule
    assert_nil MediaRules.date_display_problem({ "title" => "T" })
    assert_nil MediaRules.date_display_problem({ "date_display" => "" })
    assert_nil MediaRules.date_display_problem({ "date_display" => "April 2025" })
    assert_nil MediaRules.date_display_problem({ "date_display" => "1997" })
    assert_nil MediaRules.date_display_problem({ "date_display" => "Ongoing" })
  end

  def test_malformed_date_display_still_fails
    refute_nil MediaRules.date_display_problem({ "date_display" => "Apr 2025" })
  end

  # --- #339: the built page lives at Jekyll's slug, not the raw file name ---------------

  def test_slug_drops_em_dash_like_jekyll
    assert_equal "99-zz-test-delete-me", MediaRules.page_slug(EM_DASH_FILE)
  end

  def test_slug_of_plain_names_is_unchanged
    assert_equal "1-fda-amicus", MediaRules.page_slug("/repo/_media/1-fda-amicus.md")
  end

  def test_slug_matches_jekyll_slugify_when_available
    begin
      require "jekyll"
    rescue LoadError
      skip "jekyll not installed"
    end
    ["99-zz-test-—-delete-me", "1-fda-amicus", "a_b.c—d", "Curly “quotes” here", "café-☕-x", "--lead-and-trail--"].each do |name|
      assert_equal Jekyll::Utils.slugify(name), MediaRules.page_slug("#{name}.md"), name
      assert_equal Jekyll::Utils.slugify(name), MediaRules.fallback_slug(name), "fallback: #{name}"
    end
  end

  def test_page_found_at_jekyll_slug_address
    Dir.mktmpdir do |site|
      dir = File.join(site, "media", "99-zz-test-delete-me")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "index.html"), "<html></html>")
      assert File.exist?(MediaRules.page_path(site, EM_DASH_FILE))
    end
  end

  def test_genuinely_missing_page_is_still_missing
    Dir.mktmpdir do |site|
      refute File.exist?(MediaRules.page_path(site, EM_DASH_FILE))
      # A page at the raw (unslugged) address is not where Jekyll builds it.
      raw = File.join(site, "media", "99-zz-test-—-delete-me")
      FileUtils.mkdir_p(raw)
      File.write(File.join(raw, "index.html"), "")
      refute File.exist?(MediaRules.page_path(site, EM_DASH_FILE))
    end
  end
end
