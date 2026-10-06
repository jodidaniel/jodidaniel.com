#!/usr/bin/env ruby
# frozen_string_literal: true

# Regression tests for the Events and Media polish issues #375 and #376. No build, no browser, no network:
#
#   ruby scripts/test-event-media-polish.rb
#
#   #375  An event title is a link, so it must read as one at rest (underlined), and the
#         event card must not lift on hover: the card is not a link, only the title is.
#   #376  An item the media page's back link returns to (/#media-<slug>) must land below
#         the top edge, and no two categories in one group may share an icon.
#
# Stdlib only: plain `ruby` runs this in CI, where bundle-only gems cannot load.

require "minitest/autorun"

class EventMediaPolishTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def css
    @css ||= File.read(File.join(ROOT, "assets/css/jodidaniel.css"), encoding: "UTF-8").gsub(%r{/\*.*?\*/}m, "")
  end

  # Every style rule as [selector list, declarations], walking brace depth so a rule inside
  # an at-rule is still found. Declarations are a Hash of property => value.
  def rules
    @rules ||= begin
      found = []
      stack = []
      buffer = +""
      css.each_char do |ch|
        case ch
        when "{"
          stack << [buffer.strip, +""]
          buffer = +""
        when "}"
          head, body = stack.pop
          body << buffer
          found << [head.split(",").map(&:strip), declarations(body)] unless head.start_with?("@")
          buffer = +""
        when ";"
          buffer << ch
          stack.last[1] << buffer if stack.any?
          buffer = +""
        else
          buffer << ch
        end
      end
      found
    end
  end

  def declarations(body)
    body.split(";").filter_map do |decl|
      name, value = decl.split(":", 2)
      [name.strip, value.strip] if value
    end.to_h
  end

  # Declarations of the rules whose selector list contains exactly `selector`, merged in order.
  def style_for(selector)
    rules.select { |sels, _| sels.include?(selector) }.map(&:last).reduce({}, :merge)
  end

  # --- #375

  def test_event_card_does_not_lift_on_hover
    assert_empty rules.select { |sels, _| sels.include?(".event-item:hover") },
                 "the event card is not a link, so it must not react to hover (#375)"
    refute_includes style_for(".event-item").keys, "transition", "nothing on .event-item transitions once the lift is gone"
  end

  def test_event_title_link_reads_as_a_link_at_rest
    link = style_for(".event-body h3 a")
    refute_equal "inherit", link["color"], "the link must not just inherit the heading color (#375)"
    refute_nil link["color"], "the link needs its own color"
    decoration = link["text-decoration"].to_s
    assert_match(/\bunderline\b/, decoration, "a link title needs a resting underline, not only a hover one (#375)")
    refute_match(/\bnone\b/, decoration)
  end

  # --- #376

  def test_media_item_has_room_above_it_when_scrolled_to
    margin = style_for(".media-list li")["scroll-margin-top"]
    refute_nil margin, ".media-list li needs a scroll-margin-top so the back link does not land flush at the top (#376)"
    assert_match(/\A[0-9.]+rem\z/, margin, "use rem, so the room scales with the text size")
    assert_operator Float(margin.delete_suffix("rem")), :>=, 4
  end

  def layout
    @layout ||= File.read(File.join(ROOT, "_layouts/home.html"), encoding: "UTF-8")
  end

  def icons(list_name)
    layout[/assign #{list_name} = "([^"]+)" \| split: "\|"/, 1]&.split("|")
  end

  def test_each_media_category_in_a_group_has_its_own_icon
    %w[media_authored_icons media_coverage_icons].each do |list|
      names = icons(list)
      refute_nil names, "#{list} is gone from _layouts/home.html"
      assert_equal names.uniq, names, "#{list} repeats an icon, so two categories look the same (#376)"
      names.each do |name|
        assert_includes layout, "{%- when '#{name}' -%}", "#{list} names '#{name}' but the layout has no such icon"
      end
    end
  end

  def test_each_group_has_an_icon_per_category
    { "media_authored_cats" => "media_authored_icons", "media_coverage_cats" => "media_coverage_icons" }.each do |cats, icon_list|
      categories = layout[/assign #{cats} = "([^"]+)" \| split: "\|"/, 1].to_s.split("|")
      assert_equal categories.length, icons(icon_list).length, "#{icon_list} must pair one icon with each of #{cats}"
    end
  end
end
