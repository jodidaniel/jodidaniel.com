#!/usr/bin/env ruby
# frozen_string_literal: true

# Regression tests for scripts/a11y_rules.rb, the WCAG 2.2 AA rules
# scripts/verify-build-artifacts.rb applies to the stylesheet and the built pages.
# No build, no network:
#
#   ruby scripts/test-a11y-rules.rb

require "minitest/autorun"

# Loading the rules may fall back to the bundle (kramdown is not on plain ruby's gem path in
# CI); that must not leave `-rbundler/setup` in RUBYOPT for the caller's child processes.
ENV_BEFORE_RULES = ENV.to_h
require_relative "a11y_rules"
ENV_AFTER_RULES = ENV.to_h

class A11yRulesTest < Minitest::Test
  def test_loading_the_rules_leaves_the_environment_as_it_was
    assert_equal ENV_BEFORE_RULES, ENV_AFTER_RULES
  end

  # --- contrast math ----------------------------------------------------------------------

  def test_black_on_white_is_21_to_1
    assert_in_delta 21.0, A11yRules.contrast_ratio("#000000", "#ffffff"), 0.01
  end

  def test_three_digit_hex_expands
    assert_equal [255, 255, 255], A11yRules.parse_hex("#fff")
    assert_nil A11yRules.parse_hex("rgba(255, 255, 255, 0.7)")
    assert_nil A11yRules.parse_hex("inherit")
  end

  def test_the_retired_grays_fail_and_the_replacement_passes
    # The audit measured #8a9aaa at 2.75-2.88:1 on the card and item surfaces.
    assert_operator A11yRules.contrast_ratio("#8a9aaa", "#f8fafc"), :<, 3.0
    # #6a7a8a was 4.4:1 on white, just under AA.
    assert_operator A11yRules.contrast_ratio("#6a7a8a", "#ffffff"), :<, 4.5
    A11yRules::LIGHT_SURFACES.each do |bg|
      assert_operator A11yRules.contrast_ratio("#5f6f7f", bg), :>=, 4.5, "#5f6f7f on #{bg}"
    end
  end

  # --- stylesheet scan --------------------------------------------------------------------

  def test_css_rules_reads_nested_media_blocks
    css = "/* c { color: red } */ .a { color: #111; }\n@media (x) { .b, .c { color: #222; margin: 0 } }"
    assert_equal [[".a", { "color" => "#111" }, nil],
                  [".b, .c", { "color" => "#222", "margin" => "0" }, "@media (x)"]],
                 A11yRules.css_rules(css).reject { |sel, _d, _a| sel.start_with?("@") }
  end

  def test_low_contrast_text_flags_the_old_gray_on_a_card
    offenders = A11yRules.low_contrast_text(".event-location { color: #8a9aaa; }")
    refute_empty offenders
    assert_match(/\.event-location #8a9aaa/, offenders.first)
  end

  def test_low_contrast_text_uses_a_rules_own_background
    assert_empty A11yRules.low_contrast_text(".btn { color: #ffffff; background: #2d5a7b; }")
    refute_empty A11yRules.low_contrast_text(".btn { color: #ffffff; background: #5dd9e8; }")
  end

  def test_low_contrast_text_skips_gradient_rules_and_non_solid_colors
    assert_empty A11yRules.low_contrast_text("header { color: #ffffff; } footer { color: rgba(255, 255, 255, 0.7); }")
  end

  # --- reduced motion ---------------------------------------------------------------------

  FADE = ".animate-in { opacity: 0; animation: fadeSlideIn 0.8s ease-out forwards; }\n"
  OVERRIDE = "@media (prefers-reduced-motion: reduce) { .animate-in { animation: none; opacity: 1; transform: none; } }\n"

  def test_override_after_the_fade_in_shows_content
    assert A11yRules.reduced_motion_shows_content?(FADE + OVERRIDE)
  end

  def test_override_before_the_fade_in_loses_the_cascade
    refute A11yRules.reduced_motion_shows_content?(OVERRIDE + FADE)
  end

  def test_no_override_means_hidden_until_animated
    refute A11yRules.reduced_motion_shows_content?(FADE)
  end

  # --- built pages ------------------------------------------------------------------------

  GOOD_HOME = <<~HTML
    <!DOCTYPE html><html lang="en"><head><title>t</title></head><body>
    <a class="skip-link" href="#main">Skip to main content</a>
    <div class="site-wrapper"><header><h1>Name</h1></header>
    <main id="main" tabindex="-1">
    <section id="about"><img class="profile-image" src="/p.jpg" alt="Name" width="180" height="180"><h2>Headline</h2></section>
    <section id="expertise"><h2 class="section-title">Expertise</h2><div><h3>Card</h3></div></section>
    </main></div></body></html>
  HTML

  def test_a_good_home_page_has_no_problems
    assert_equal [], A11yRules.page_problems(GOOD_HOME, home: true)
  end

  def test_missing_main_and_skip_link_are_reported
    html = GOOD_HOME.sub('<main id="main" tabindex="-1">', "<div>").sub("</main>", "</div>")
                    .sub(/<a class="skip-link".*?<\/a>/m, "")
    problems = A11yRules.page_problems(html, home: true)
    assert(problems.any? { |p| p.include?("<main>") }, problems.inspect)
    assert(problems.any? { |p| p.include?("skip link") }, problems.inspect)
  end

  def test_a_span_section_title_is_reported
    html = GOOD_HOME.sub('<h2 class="section-title">Expertise</h2>', '<span class="section-title">Expertise</span>')
    problems = A11yRules.page_problems(html, home: true)
    assert(problems.any? { |p| p.include?("not <h2>") }, problems.inspect)
  end

  def test_a_skipped_heading_level_is_reported
    html = GOOD_HOME.sub("<h2>Headline</h2>", "").sub('<h2 class="section-title">Expertise</h2>', '<span class="section-title">Expertise</span>')
    problems = A11yRules.page_problems(html, home: true)
    assert(problems.any? { |p| p.include?("jumps from h1 to h3") }, problems.inspect)
  end

  def test_an_unsized_image_is_reported
    html = GOOD_HOME.sub(' width="180" height="180"', "")
    assert(A11yRules.page_problems(html, home: true).any? { |p| p.include?("width/height") })
  end

  def test_a_heading_outside_main_is_reported
    html = GOOD_HOME.sub("<header><h1>Name</h1></header>", "<header><h1>Name</h1></header><h2>Stray</h2>")
    assert(A11yRules.page_problems(html, home: true).any? { |p| p.include?("outside <main>") })
  end

  def test_the_skip_link_must_be_first
    html = GOOD_HOME.sub('<div class="site-wrapper">', '<div class="site-wrapper"><a href="/x">x</a>')
    # move the skip link after the other link
    html = html.sub(/<a class="skip-link".*?<\/a>/m, "").sub("</a>", '</a><a class="skip-link" href="#main">Skip</a>')
    assert(A11yRules.page_problems(html, home: true).any? { |p| p.include?("not the first link") })
  end
end
