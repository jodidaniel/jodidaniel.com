#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds the site from a temp copy with the link preview image setting changed
# (_data/settings.yml `share.image`, the "Link Preview Image" upload in /admin)
# and checks that the built pages follow it: a changed setting changes the
# output, a cleared one means no image tags, and the gated coming-soon page
# follows it too. The image paths below are invented and need not exist, so
# the test never depends on what she has uploaded or published.
#
#   ruby scripts/test-share-image.rb
#
# Each scenario copies the tracked source into a temp dir outside the repo (no
# .git, so nothing run there can reach origin), edits it there only, and builds.

require "minitest/autorun"
require "yaml"
require "cgi"
require "tmpdir"
require "fileutils"
require "open3"

class ShareImageTest < Minitest::Test
  REPO_ROOT = File.expand_path("..", __dir__)
  SITE_URL = YAML.safe_load(File.read(File.join(REPO_ROOT, "_config.yml"), encoding: "utf-8"))["url"].to_s
  UPLOAD = "/assets/images/uploads/test-card-a.png"
  OTHER_UPLOAD = "/assets/images/uploads/test-card-b.png"

  # Builds a copy of the repo whose settings are the live ones with `share`
  # (and `site_live`) replaced, and returns { page_path => head }.
  def build(share:, live: true)
    Dir.mktmpdir("share-image-") do |tmp|
      src = File.join(tmp, "src")
      tracked, status = Open3.capture2("git", "-C", REPO_ROOT, "ls-files", "-z")
      assert status.success?, "git ls-files failed"
      tracked.split("\0").each do |rel|
        next unless File.file?(File.join(REPO_ROOT, rel))
        FileUtils.mkdir_p(File.dirname(File.join(src, rel)))
        FileUtils.cp(File.join(REPO_ROOT, rel), File.join(src, rel))
      end
      edit_yaml(File.join(src, "_data", "settings.yml")) { |data| data.merge("site_live" => live, "share" => share) }

      site = File.join(tmp, "site")
      out, status = Open3.capture2e({ "JEKYLL_ENV" => "production" }, "bundle", "exec", "jekyll", "build", "--quiet",
                                    "--source", src, "--destination", site, chdir: REPO_ROOT)
      assert status.success?, "jekyll build failed:\n#{out}"
      pages = { "home" => File.join(site, "index.html") }
      media = Dir[File.join(site, "media", "*", "index.html")].min
      pages["media"] = media if media
      pages.transform_values { |f| File.read(f, encoding: "utf-8")[%r{<head>.*?</head>}m].to_s }
    end
  end

  def edit_yaml(path)
    data = YAML.safe_load(File.read(path, encoding: "utf-8")) || {}
    File.write(path, YAML.dump(yield(data)))
  end

  def metas(head)
    head.scan(/<meta\s+([^>]*?)\s*\/?>/m).each_with_object(Hash.new { |h, k| h[k] = [] }) do |(attrs), acc|
      key = attrs[/(?:property|name)="([^"]+)"/, 1]
      acc[key] << CGI.unescapeHTML(attrs[/content="([^"]*)"/, 1].to_s) if key
    end
  end

  def test_the_setting_drives_og_and_twitter_image_on_home_and_media_pages
    pages = build(share: { "image" => UPLOAD, "image_alt" => "A card & more" })
    assert_equal %w[home media], pages.keys, "need the home page and a media page"
    pages.each do |label, head|
      m = metas(head)
      assert_equal ["#{SITE_URL}#{UPLOAD}"], m["og:image"], "#{label} og:image"
      assert_equal ["#{SITE_URL}#{UPLOAD}"], m["twitter:image"], "#{label} twitter:image"
      assert_equal ["summary_large_image"], m["twitter:card"], label
      assert_equal ["A card & more"], m["og:image:alt"], label
      assert_equal ["A card & more"], m["twitter:image:alt"], label
    end
  end

  def test_a_changed_setting_changes_the_output
    first = metas(build(share: { "image" => UPLOAD })["home"])["og:image"]
    second = metas(build(share: { "image" => OTHER_UPLOAD })["home"])["og:image"]
    assert_equal ["#{SITE_URL}#{UPLOAD}"], first
    assert_equal ["#{SITE_URL}#{OTHER_UPLOAD}"], second
  end

  def test_a_blank_setting_means_no_image_tags_and_the_small_card
    build(share: { "image" => "", "image_alt" => "" }).each do |label, head|
      m = metas(head)
      %w[og:image twitter:image og:image:alt twitter:image:alt].each { |key| refute m.key?(key), "#{label}: #{key} with no image chosen" }
      assert_equal ["summary"], m["twitter:card"], label
    end
  end

  def test_the_gated_page_with_no_image_serves_the_name_but_no_image
    m = metas(build(share: { "image" => "" }, live: false)["home"])
    refute m.key?("og:image")
    assert_equal ["summary"], m["twitter:card"]
    assert_equal 1, m["twitter:title"].size
  end

  def test_the_gated_page_follows_the_setting_and_serves_no_person_data
    head = build(share: { "image" => UPLOAD, "image_alt" => "A card" }, live: false)["home"]
    m = metas(head)
    assert_equal ["#{SITE_URL}#{UPLOAD}"], m["og:image"]
    assert_equal ["#{SITE_URL}#{UPLOAD}"], m["twitter:image"]
    assert_equal ["summary_large_image"], m["twitter:card"]
    refute_includes head, "ld+json"
  end
end
