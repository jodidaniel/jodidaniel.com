#!/usr/bin/env ruby
# frozen_string_literal: true

# Regression test for issue #360: on phones the floating back-to-top button
# covered card text. No build, no browser, no network:
#
#   ruby scripts/test-back-to-top-clearance.rb
#
# Card text ends (.site-wrapper padding + phone .container padding) from the
# viewport's right edge. The button is fixed at `right`, `width` wide, so it
# stays clear of that text exactly when right + width fits inside that gutter.
# Everything is in rem, so the relation holds at every phone width. Stdlib only.

require "minitest/autorun"

class BackToTopClearanceTest < Minitest::Test
  CSS = File.expand_path("../assets/css/jodidaniel.css", __dir__)

  def css
    @css ||= File.read(CSS, encoding: "UTF-8").gsub(%r{/\*.*?\*/}m, "")
  end

  # The body of the first `selector { ... }` in `source` (declarations only).
  def rule_body(source, selector)
    source[/(?:\A|\})\s*#{Regexp.escape(selector)}\s*\{([^}]*)\}/m, 1]
  end

  # Everything between the braces of the `@media (max-width: 767px)` block.
  def phone_block
    start = css.index(/@media \(max-width: 767px\)\s*\{/)
    refute_nil start, "the 767px phone media query is gone"
    from = css.index("{", start) + 1
    depth = 1
    i = from
    while depth.positive? && i < css.length
      depth += 1 if css[i] == "{"
      depth -= 1 if css[i] == "}"
      i += 1
    end
    css[from...(i - 1)]
  end

  def rem(body, property)
    value = body && body[/(?:\A|[\s;])#{property}\s*:\s*([0-9.]+)rem\s*;/, 1]
    refute_nil value, "#{property} must be a plain rem value"
    Float(value)
  end

  def test_phone_button_sits_in_the_gutter_beside_card_text
    button = rule_body(phone_block, ".back-to-top")
    refute_nil button, ".back-to-top has no rule in the phone media query"

    wrapper = rem(rule_body(css, ".site-wrapper"), "padding")
    container = rem(rule_body(phone_block, ".container"), "padding")
    gutter = wrapper + container

    footprint = rem(button, "right") + rem(button, "width")
    assert_operator footprint, :<=, gutter,
                    "phone back-to-top spans #{footprint}rem from the right edge but card text " \
                    "ends #{gutter}rem from it, so the button covers text (#360)"
    assert_equal rem(button, "width"), rem(button, "height"), "the button must stay round"
  end
end
