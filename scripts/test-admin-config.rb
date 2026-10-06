#!/usr/bin/env ruby
# frozen_string_literal: true

# Regression tests for the /admin field config in admin/collections.site.yml (issue #358).
# No build, no network:
#
#   ruby scripts/test-admin-config.rb

require "minitest/autorun"
require "yaml"

class AdminConfigTest < Minitest::Test
  CONFIG = File.expand_path("../admin/collections.site.yml", __dir__)

  def collections
    @collections ||= YAML.safe_load(File.read(CONFIG, encoding: "UTF-8"))
  end

  # Every field hash in the config, however deeply nested (fields, field, files).
  def each_field(node, &block)
    case node
    when Array
      node.each { |child| each_field(child, &block) }
    when Hash
      yield node if node.key?("widget")
      node.each_value { |child| each_field(child, &block) }
    end
  end

  def find_in_file(file_name, field_name)
    each_file = collections.flat_map { |c| c["files"] || [] }.find { |f| f["name"] == file_name }
    found = nil
    each_field(each_file) { |f| found ||= f if f["name"] == field_name }
    found
  end

  # --- #358: Decap appends its own "(optional)" to the label of every required: false field

  def test_no_label_spells_out_optional
    labels = []
    each_field(collections) { |f| labels << f["label"].to_s }
    refute_empty labels
    doubled = labels.grep(/\(optional\)/i)
    assert_empty doubled, "Decap adds '(optional)' itself; drop it from #{doubled.inspect}"
  end

  # --- #358: the About text fields render Markdown (markdownify in _layouts/home.html), so the
  # editor must be told the `**` pairs in the saved copy are bold markup, not stray marks.
  # Decap renders hints as Markdown too, so the hint escapes the asterisks (`\*\*`) to show them.

  def test_markdown_about_fields_explain_the_bold_markup
    %w[lead bio].each do |name|
      field = find_in_file("about", name)
      refute_nil field, "about.#{name} is missing from the admin config"
      hint = field["hint"].to_s
      assert_includes hint, "\\*\\*", "about.#{name} hint must show the literal asterisks (escaped for Decap's Markdown hint)"
      assert_match(/bold/i, hint, "about.#{name} hint must say what the asterisks do")
    end
  end
end
