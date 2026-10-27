#!/usr/bin/env ruby
# frozen_string_literal: true

# Regression tests for _plugins/site_meta_from_settings.rb: the site title, the
# launch page title and the launch Google description come from
# _data/settings.yml (`seo:`), so /admin can edit them. No build, no network, no
# Jekyll install:
#
#   ruby scripts/test-site-meta.rb

require "minitest/autorun"
require "yaml"

# Liquid is a Jekyll dependency, so on a CI runner it exists only in the bundle
# (`ruby` alone cannot see it), while minitest is a system gem the bundle does
# not carry. minitest is already loaded above, so a LoadError here means the
# bundle's gems are not on the load path yet: put them there from the Gemfile
# (this repo's, wherever the script is run from) and try again.
begin
  require "liquid"
rescue LoadError
  ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
  require "bundler/setup"
  require "liquid"
end

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
require File.join(ROOT, "_plugins", "site_meta_from_settings.rb")

class SiteMetaTest < Minitest::Test
  Page = Struct.new(:data)
  Site = Struct.new(:config, :data, :pages)

  SETTINGS = {
    "seo" => {
      "site_title" => "Edited Name",
      "launch_title" => "Edited Role",
      "launch_description" => "Edited description."
    }
  }.freeze

  def run_hook(site)
    _, _, block = Jekyll::Hooks::REGISTERED.find { |owner, event, _| owner == :site && event == :post_read }
    refute_nil block, "the plugin must register a :site :post_read hook"
    block.call(site)
    site
  end

  def site_with(settings)
    Site.new({ "title" => "Fallback Name" }, { "settings" => settings },
             [Page.new({ "layout" => "home" }), Page.new({ "layout" => "media" })])
  end

  def test_settings_values_replace_title_description_and_home_page_title
    site = run_hook(site_with(SETTINGS))
    assert_equal "Edited Name", site.config["title"]
    assert_equal "Edited description.", site.config["description"]
    assert_equal "Edited Role", site.pages[0].data["title"]
  end

  def test_only_the_home_page_gets_the_launch_title
    site = run_hook(site_with(SETTINGS))
    refute site.pages[1].data.key?("title"), "a non-home page must keep its own title"
  end

  def test_blank_or_missing_fields_leave_values_alone
    [{}, { "seo" => nil }, { "seo" => { "site_title" => "  ", "launch_title" => "", "launch_description" => nil } }].each do |settings|
      site = run_hook(site_with(settings))
      assert_equal "Fallback Name", site.config["title"], settings.inspect
      refute site.config.key?("description"), settings.inspect
      refute site.pages[0].data.key?("title"), settings.inspect
    end
  end

  def test_missing_settings_file_does_not_raise
    site = run_hook(Site.new({ "title" => "Fallback Name" }, {}, []))
    assert_equal "Fallback Name", site.config["title"]
  end

  def test_an_ampersand_in_the_site_title_is_kept_as_data
    settings = { "seo" => { "site_title" => "Jodi Daniel & Co" } }
    site = run_hook(site_with(settings))
    assert_equal "Jodi Daniel & Co", site.config["title"]
  end

  # The gated <title> is printed by the layouts themselves ({% seo %} escapes its
  # own), so a site name with an "&" must go through `escape` there. Parsed with
  # Liquid, not scanned, so the check follows the template's real structure.
  LAYOUTS = %w[home media].freeze

  # The one `capture` block that builds the JSON-LD document (media.html prints it inside
  # <script type="application/ld+json">, after turning every "<" into \u003c). Only a
  # variable inside it may use `jsonify`; everywhere else, HTML context, only `escape` is
  # right, since jsonify output is not HTML-safe ("&" stays raw) and its quotes break out of
  # an attribute.
  JSON_LD_CAPTURES = %w[media_json].freeze

  def parse_layout(layout, source = nil)
    Liquid::Template.register_tag("seo", Class.new(Liquid::Tag))
    Liquid::Template.register_tag("inline_css", Class.new(Liquid::Tag))
    source ||= File.read(File.join(ROOT, "_layouts", "#{layout}.html"), encoding: "UTF-8")
    Liquid::Template.parse(source)
  end

  def visit(node, klass, &block)
    Liquid::ParseTreeVisitor.for(node).tap do |visitor|
      visitor.add_callback_for(klass) do |found|
        block.call(found)
        nil
      end
    end.visit
  end

  # (Liquid 4 has no reader for a capture's target name, so read @to.)
  # [[variable, inside_json_ld], ...] for every `{{ site.title ... }}` the template prints.
  def site_title_variables(layout, source = nil)
    template = parse_layout(layout, source)
    json_ld = []
    visit(template.root, Liquid::Capture) do |capture|
      visit(capture, Liquid::Variable) { |variable| json_ld << variable } if JSON_LD_CAPTURES.include?(capture.instance_variable_get(:@to))
    end
    found = []
    visit(template.root, Liquid::Variable) do |variable|
      name = variable.name
      next unless name.is_a?(Liquid::VariableLookup) && name.name == "site" && name.lookups == ["title"]

      found << [variable, json_ld.any? { |candidate| candidate.equal?(variable) }]
    end
    found
  end

  def encoder_problems(found)
    found.filter_map do |variable, in_json_ld|
      allowed = in_json_ld ? %w[escape jsonify] : %w[escape]
      "site.title through #{variable.filters.map(&:first).inspect} (needs one of #{allowed.inspect})" if (variable.filters.map(&:first) & allowed).empty?
    end
  end

  def test_layouts_escape_the_site_title_they_print
    LAYOUTS.each do |layout|
      found = site_title_variables(layout)
      refute_empty found, "_layouts/#{layout}.html no longer prints site.title; update this test"
      assert_empty encoder_problems(found), "_layouts/#{layout}.html prints site.title with the wrong encoder"
    end
  end

  def test_media_layout_still_prints_the_site_title_inside_the_json_ld_capture
    assert site_title_variables("media").any? { |_, in_json_ld| in_json_ld },
           "media.html no longer prints site.title in the JSON-LD capture (#{JSON_LD_CAPTURES.inspect}); update this test"
  end

  def test_jsonify_is_not_accepted_for_the_site_title_in_html
    in_title = "<title>{{ page.title | escape }} | {{ site.title | jsonify }}</title>"
    refute_empty encoder_problems(site_title_variables("media", in_title)), "jsonify in <title> must be rejected"
    in_attribute = '<meta property="og:site_name" content="{{ site.title | jsonify }}" />'
    refute_empty encoder_problems(site_title_variables("media", in_attribute)), "jsonify in an attribute must be rejected"
    unescaped = "<title>{{ site.title }}</title>"
    refute_empty encoder_problems(site_title_variables("media", unescaped)), "an unencoded site.title must be rejected"
    json_ld = "{% capture media_json %}{\"name\":{{ site.title | jsonify }}}{% endcapture %}"
    assert_empty encoder_problems(site_title_variables("media", json_ld)), "jsonify inside the JSON-LD capture is correct"
  end

  # The two literals the fields replaced are gone from where only a commit could
  # edit them. (The fields themselves may be blank: the admin hints promise a
  # fallback, so nothing here requires them filled in.)
  def settings
    @settings ||= YAML.safe_load(File.read(File.join(ROOT, "_data", "settings.yml"), encoding: "UTF-8"))
  end

  def test_settings_file_declares_the_seo_keys
    %w[site_title launch_title launch_description].each do |key|
      assert settings["seo"].is_a?(Hash) && settings["seo"].key?(key), "_data/settings.yml seo.#{key} must exist"
    end
  end

  def test_launch_values_are_not_also_hardcoded_in_config_or_index
    config = YAML.safe_load(File.read(File.join(ROOT, "_config.yml"), encoding: "UTF-8"))
    refute config.key?("description"), "_config.yml description would be a second, unedited source"
    front = File.read(File.join(ROOT, "index.html"), encoding: "UTF-8").split(/^---\s*$/, 3)[1]
    refute YAML.safe_load(front).key?("title"), "index.html title would be a second, unedited source"
  end
end
