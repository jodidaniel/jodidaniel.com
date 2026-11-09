#!/usr/bin/env ruby
# frozen_string_literal: true

# Regression tests for _plugins/share_image_from_settings.rb: the link-preview
# picture comes from _data/settings.yml (`share.image`, `share.image_alt`), so
# /admin can change it, and it is set only while the site is live. No build, no
# network, no Jekyll install:
#
#   ruby scripts/test-share-image.rb

require "minitest/autorun"
require "tmpdir"
require "fileutils"

# The plugin registers a Jekyll hook when loaded; capture it instead of booting
# Jekyll, so the test runs the real hook body against a stand-in site.
module Jekyll
  module Hooks
    REGISTERED = []
    def self.register(owner, event, &block)
      REGISTERED << [owner, event, block]
    end
  end
end

ROOT = File.expand_path("..", __dir__)
require File.join(ROOT, "_plugins", "share_image_from_settings.rb")

class ShareImageTest < Minitest::Test
  Doc = Struct.new(:data)
  Collection = Struct.new(:docs)
  Site = Struct.new(:source, :data, :pages, :collections)

  def settings(live: true, image: "/assets/images/uploads/card.png", alt: "Portrait of A. Person")
    { "site_live" => live, "share" => { "image" => image, "image_alt" => alt } }
  end

  def image_for(settings, exists: true, size: [1200, 630])
    JodiShareImage.image(settings, exists: ->(_) { exists }, png_size: ->(_) { size })
  end

  def test_live_site_gets_path_alt_and_size
    assert_equal({ "path" => "/assets/images/uploads/card.png", "alt" => "Portrait of A. Person", "width" => 1200, "height" => 630 },
                 image_for(settings))
  end

  def test_coming_soon_site_gets_no_image
    assert_nil image_for(settings(live: false))
    assert_nil image_for(settings(live: "true")), "only a real boolean true opens the gate"
  end

  def test_blank_missing_or_unsafe_path_sets_nothing
    [nil, "", "assets/card.png", "https://example.com/card.png", "/../card.png"].each do |path|
      assert_nil image_for(settings(image: path)), path.inspect
    end
    assert_nil image_for(settings, exists: false), "a file that is not in the site"
  end

  def test_blank_alt_is_left_out_and_unknown_size_is_left_out
    assert_equal({ "path" => "/assets/images/uploads/card.png" }, image_for(settings(alt: "  "), size: nil))
  end

  def test_png_size_reads_the_header_and_ignores_other_files
    Dir.mktmpdir do |dir|
      png = File.join(dir, "a.png")
      File.binwrite(png, JodiShareImage::PNG_SIGNATURE + [13].pack("N") + "IHDR" + [640, 320].pack("NN") + "\0" * 5)
      jpg = File.join(dir, "a.jpg")
      File.binwrite(jpg, "\xFF\xD8\xFF" + "\0" * 40)
      assert_equal [640, 320], JodiShareImage.png_size(png)
      assert_nil JodiShareImage.png_size(jpg)
      assert_nil JodiShareImage.png_size(File.join(dir, "missing.png"))
    end
  end

  def test_the_committed_default_card_is_a_1200_by_630_png
    assert_equal [1200, 630], JodiShareImage.png_size(File.join(ROOT, "assets", "images", "uploads", "share-card.png"))
  end

  def run_hook(site)
    _, _, hook = Jekyll::Hooks::REGISTERED.find { |owner, event, _| owner == :site && event == :post_read }
    hook.call(site)
  end

  def test_hook_sets_home_and_media_pages_only
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "img"))
      File.binwrite(File.join(dir, "img", "card.png"), JodiShareImage::PNG_SIGNATURE + [13].pack("N") + "IHDR" + [1200, 630].pack("NN"))
      home = Doc.new({ "layout" => "home" })
      other = Doc.new({ "layout" => "not-found" })
      item = Doc.new({ "layout" => "media" })
      data = { "settings" => settings(image: "/img/card.png") }
      run_hook(Site.new(dir, data, [home, other], { "media" => Collection.new([item]) }))
      assert_equal "/img/card.png", home.data["image"]["path"]
      assert_equal [1200, 630], item.data["image"].values_at("width", "height")
      refute other.data.key?("image")
    end
  end

  def test_hook_sets_nothing_on_the_coming_soon_site
    home = Doc.new({ "layout" => "home" })
    item = Doc.new({ "layout" => "media" })
    # The committed default card exists, so only the gate keeps it off.
    gated = settings(live: false, image: "/assets/images/uploads/share-card.png")
    run_hook(Site.new(ROOT, { "settings" => gated }, [home], { "media" => Collection.new([item]) }))
    refute home.data.key?("image")
    refute item.data.key?("image")
  end
end
