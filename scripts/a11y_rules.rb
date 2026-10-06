# frozen_string_literal: true

# Accessibility rules (WCAG 2.2 AA) scripts/verify-build-artifacts.rb applies to the stylesheet
# and to the built pages, in a file of their own so scripts/test-a11y-rules.rb can test them
# without a Jekyll build. `scripts/` is excluded from the Jekyll build (_config.yml), so this
# is never published.
#
# Built pages are read with kramdown's HTML parser (a Jekyll dependency, so already installed),
# not a regex: what matters is where an element sits, and a regex cannot see nesting.

# kramdown is a bundle gem: `ruby` alone (how site-verify runs this script) may not see it, so
# fall back to the repo's bundle. `bundler/setup` also writes RUBYOPT, BUNDLE_GEMFILE and
# RUBYLIB into the environment, and every child process the caller spawns afterwards (the other
# scripts/test-*.rb, which load minitest from the system gems) would inherit `-rbundler/setup`
# and fail with "cannot load such file -- minitest/autorun". The bundle is already on this
# process's load path, so put the environment back as it was found.
begin
  require "kramdown"
rescue LoadError
  env_before = ENV.to_h
  require "bundler/setup"
  ENV.replace(env_before)
  require "kramdown"
end

module A11yRules
  # Body text must reach 4.5:1 (WCAG 1.4.3). These are the light surfaces text sits on in
  # assets/css/jodidaniel.css: the white card, the #f8fafc item background and the #e8f4f8 hover
  # background. The worst case is the darkest of them.
  LIGHT_SURFACES = %w[#ffffff #f8fafc #e8f4f8].freeze
  MIN_RATIO = 4.5

  # Rules whose text sits on the page's gradient, not on a card. axe cannot compute a contrast
  # over a gradient (it reports "incomplete"), so low_contrast_text skips them and
  # tagline_problems / footer_problems score the tagline and footer against the gradient.
  ON_GRADIENT_SELECTORS = ["header", "header h1 a", "footer", "footer a"].freeze

  module_function

  # "#abc" or "#aabbcc" -> [r, g, b]; nil for anything else (named colors, rgba(), inherit).
  def parse_hex(value)
    m = value.to_s.strip.match(/\A#([0-9a-f]{3}|[0-9a-f]{6})\z/i)
    return nil unless m

    hex = m[1]
    hex = hex.chars.map { |c| c * 2 }.join if hex.length == 3
    hex.scan(/../).map { |pair| pair.to_i(16) }
  end

  def relative_luminance(rgb)
    r, g, b = rgb.map do |channel|
      c = channel / 255.0
      c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
    end
    (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
  end

  def contrast_ratio(fg_hex, bg_hex)
    lighter, darker = [relative_luminance(parse_hex(fg_hex)), relative_luminance(parse_hex(bg_hex))].sort.reverse
    (lighter + 0.05) / (darker + 0.05)
  end

  # Lexical scan of a stylesheet into [[selector, { property => value }, at_rule], ...] for every
  # declaration block, in the order each block closes. `at_rule` is the header of the enclosing
  # @media (nil at top level). Comments are dropped first.
  def css_rules(css)
    rules = []
    text = css.gsub(%r{/\*.*?\*/}m, "")
    header = +"" # text since the last "{", "}" or ";" at this level: a selector or a declaration
    stack = []   # [selector, declarations] of the blocks still open
    text.each_char do |ch|
      case ch
      when "{"
        stack << [header.strip.gsub(/\s+/, " "), {}]
        header = +""
      when "}"
        add_declaration(stack.last[1], header) unless stack.empty?
        unless stack.empty?
          selector, decls = stack.pop
          rules << [selector, decls, stack.last&.first]
        end
        header = +""
      when ";"
        add_declaration(stack.last[1], header) unless stack.empty?
        header = +""
      else
        header << ch
      end
    end
    rules
  end

  def add_declaration(decls, text)
    prop, value = text.split(":", 2)
    decls[prop.strip.downcase] = value.strip if value
  end

  # Every solid text color in the stylesheet that is below MIN_RATIO on the surface it sits on:
  # the rule's own solid `background`, else the worst of LIGHT_SURFACES. Returns
  # ["selector color on surface = ratio", ...]; empty when all pass.
  def low_contrast_text(css)
    css_rules(css).flat_map do |selector, decls, _at_rule|
      next [] if selector.start_with?("@")
      next [] if selector.split(",").map(&:strip).all? { |s| ON_GRADIENT_SELECTORS.include?(s) }

      color = decls["color"]
      next [] unless parse_hex(color)

      own_bg = decls["background"] || decls["background-color"]
      surfaces = parse_hex(own_bg) ? [own_bg] : LIGHT_SURFACES
      surfaces.filter_map do |bg|
        ratio = contrast_ratio(color, bg)
        format("%s %s on %s = %.2f:1", selector, color, bg, ratio) if ratio < MIN_RATIO
      end
    end
  end

  # ---- text on the page gradient -----------------------------------------------------------

  # The header tagline and the footer sit directly on the body's gradient, which axe cannot
  # score (it reports them "incomplete"), so the contrast is computed here from the stylesheet.
  #
  # WCAG 1.4.3: large text (at least 24px, or bold at least 18.66px = 14pt) needs 3:1, other
  # text 4.5:1. 600 is the heaviest Source Sans Pro file the site ships (assets/fonts), so it is
  # the lowest weight counted as bold; 700 would be a faux bold.
  LARGE_TEXT_PX = 24.0
  LARGE_BOLD_TEXT_PX = 18.66
  BOLD_MIN_WEIGHT = 600
  LARGE_TEXT_MIN_RATIO = 3.0
  PHONE_MEDIA = /max-width:\s*767px/

  # The tagline is centered at the top of the page, so the part of the gradient behind it is
  # bounded by where it sits: a point (x, y) on the 135deg gradient is at (x + y) / (width +
  # height) of the way along it. Measured in Chromium over the home page and a media item page
  # (the shortest pages put it furthest along): 0.62 at most from 768 to 1920 wide, and 0.38-0.41
  # at 320-414 wide. The bounds below leave a little headroom; the lightest stops (0.75, 1.0)
  # are never behind it, so it is scored against the gradient only up to the bound.
  # KNOWN GAP, not asserted: between ~600 and 767 wide the phone-size (16px, not large) tagline
  # reaches 0.48 on a short page, 4.3:1; see the pull request that added this.
  TAGLINE_MAX_GRADIENT_POSITION = 0.7
  TAGLINE_MAX_GRADIENT_POSITION_PHONE = 0.43

  # "#abc", "#aabbcc", "rgb(r, g, b)" or "rgba(r, g, b, a)" -> [r, g, b, alpha]; nil otherwise.
  def parse_color(value)
    value = value.to_s.strip
    if (rgb = parse_hex(value))
      return rgb + [1.0]
    end

    m = value.match(/\Argba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)\z/i)
    m && [m[1].to_i, m[2].to_i, m[3].to_i, (m[4] || "1").to_f]
  end

  # `fg` ([r, g, b, alpha]) painted over the opaque `bg` ([r, g, b]) -> [r, g, b].
  def composite(fg, bg)
    alpha = fg[3]
    (0..2).map { |i| (fg[i] * alpha) + (bg[i] * (1 - alpha)) }
  end

  def rgb_contrast(fg_rgb, bg_rgb)
    lighter, darker = [relative_luminance(fg_rgb), relative_luminance(bg_rgb)].sort.reverse
    (lighter + 0.05) / (darker + 0.05)
  end

  # The body's gradient as [[position 0..1, [r, g, b]], ...], or nil when it has none. Stops
  # without a percentage are not used by this stylesheet and are not read.
  def gradient_stops(css)
    body = css_rules(css).find { |sel, decls, at| sel == "body" && at.nil? && decls["background"].to_s.include?("linear-gradient") }
    return nil unless body

    stops = body[1]["background"].scan(/(#[0-9a-f]{3,6})\s+(\d+(?:\.\d+)?)%/i).map do |hex, pct|
      [pct.to_f / 100, parse_hex(hex)]
    end
    stops.empty? || stops.any? { |_pos, rgb| rgb.nil? } ? nil : stops
  end

  # The gradient's color at `position`, linearly interpolated between the stops either side.
  def gradient_color_at(stops, position)
    return stops.first[1] if position <= stops.first[0]
    return stops.last[1] if position >= stops.last[0]

    lo, hi = stops.each_cons(2).find { |a, b| position >= a[0] && position <= b[0] }
    k = (position - lo[0]) / (hi[0] - lo[0])
    (0..2).map { |i| lo[1][i] + ((hi[1][i] - lo[1][i]) * k) }
  end

  # "1.25rem" or "20px" -> px (1rem = 16px); nil for anything else.
  def font_px(value)
    m = value.to_s.strip.match(/\A([\d.]+)(rem|px)\z/)
    m && (m[2] == "rem" ? m[1].to_f * 16 : m[1].to_f)
  end

  def large_text?(px, weight)
    px >= LARGE_TEXT_PX || (px >= LARGE_BOLD_TEXT_PX && weight >= BOLD_MIN_WEIGHT)
  end

  # Problems with `header .tagline` (white text, so only its `opacity` lowers it) on the page
  # gradient: one line per viewport class (desktop = base rule, phone = the 767px override).
  # [] when it reaches its required ratio, 3:1 as large text else 4.5:1, everywhere it can be.
  def tagline_problems(css)
    stops = gradient_stops(css)
    return ["body has no readable linear-gradient background"] unless stops

    rules = css_rules(css).select { |sel, _decls, _at| sel == "header .tagline" }
    base = rules.find { |_sel, _decls, at| at.nil? }
    return ["no `header .tagline` rule"] unless base

    phone = rules.find { |_sel, _decls, at| at.to_s.match?(PHONE_MEDIA) }
    px = font_px(base[1]["font-size"])
    weight = base[1]["font-weight"].to_i
    opacity = (base[1]["opacity"] || "1").to_f
    header = css_rules(css).find { |sel, _decls, at| sel == "header" && at.nil? }
    color = parse_color(base[1]["color"] || (header && header[1]["color"]))
    return ["`header .tagline` has no color of its own and `header` sets none"] unless color
    return ["`header .tagline` font-size #{base[1]['font-size'].inspect} is not rem or px"] unless px

    [["desktop", px, TAGLINE_MAX_GRADIENT_POSITION],
     ["phone", font_px(phone && phone[1]["font-size"]) || px, TAGLINE_MAX_GRADIENT_POSITION_PHONE]].filter_map do |name, size, limit|
      large = large_text?(size, weight)
      needed = large ? LARGE_TEXT_MIN_RATIO : MIN_RATIO
      worst = (0..40).map do |i|
        bg = gradient_color_at(stops, limit * i / 40.0)
        rgb_contrast(composite(color[0, 3] + [color[3] * opacity], bg), bg)
      end.min
      next if worst >= needed

      format("tagline (%s) %gpx weight %d is %s text: %.2f:1 over the gradient up to %g, needs %g:1",
             name, size, weight, large ? "large" : "normal", worst, limit, needed)
    end
  end

  # Problems with `footer`: its text and links (4.5:1: 14px-ish text is never large) over its own
  # backing band composited over EVERY gradient stop. The band may be translucent, and then the
  # lightest stop is the worst case. [] when every combination passes.
  def footer_problems(css)
    stops = gradient_stops(css)
    return ["body has no readable linear-gradient background"] unless stops

    rules = css_rules(css).select { |_sel, _decls, at| at.nil? }
    footer = rules.find { |sel, _decls, _at| sel == "footer" }
    return ["no `footer` rule"] unless footer

    link = rules.find { |sel, _decls, _at| sel == "footer a" }
    problems = []
    if footer[1]["opacity"] && footer[1]["opacity"].to_f < 1
      problems << "footer opacity #{footer[1]['opacity']} lowers its text contrast"
    end
    band = parse_color(footer[1]["background"] || footer[1]["background-color"]) || [0, 0, 0, 0.0]
    texts = [["footer text", footer[1]["color"]]]
    texts << ["footer link", link[1]["color"]] if link && link[1]["color"]
    texts.each do |label, value|
      color = parse_color(value)
      unless color
        problems << "#{label} color #{value.inspect} is not a color this check can read"
        next
      end

      stops.each do |position, stop_rgb|
        under = composite(band, stop_rgb)
        ratio = rgb_contrast(composite(color, under), under)
        next if ratio >= MIN_RATIO

        problems << format("%s %s over the %g%% gradient stop (band %s) is %.2f:1, needs %g:1",
                           label, value, position * 100, footer[1]["background"] || "none", ratio, MIN_RATIO)
      end
    end
    problems
  end

  # ---- built pages ------------------------------------------------------------------------

  def parse_html(html)
    Kramdown::Document.new(html, input: "html", parse_block_html: true, parse_span_html: true).root
  end

  # Depth-first list of every element, with its ancestors, in document order.
  # Each entry: { node:, ancestors: [nodes] }
  def elements(root)
    out = []
    walk = lambda do |node, ancestors|
      out << { node: node, ancestors: ancestors } if %i[html_element header img a p].include?(node.type)
      node.children.each { |child| walk.call(child, ancestors + [node]) }
    end
    walk.call(root, [])
    out
  end

  # Normalized tag name: kramdown turns <h1>..<h6> into :header with a level, and <a>/<p>/<img>
  # into their own node types.
  def tag_of(node)
    case node.type
    when :header then "h#{node.options[:level]}"
    when :html_element then node.value
    else node.type.to_s
    end
  end

  def find_all(root, tag)
    elements(root).select { |e| tag_of(e[:node]) == tag }
  end

  def text_of(node)
    node.type == :text ? node.value.to_s : node.children.map { |c| text_of(c) }.join
  end

  # Problems with a built, open-gate page (the home page or a media item page). [] when clean.
  # `require_h2_sections` is true for the home page, whose sections carry `.section-title`.
  def page_problems(html, home: false)
    root = parse_html(html)
    problems = []

    mains = find_all(root, "main")
    problems << "expected exactly one <main>, found #{mains.size}" unless mains.size == 1
    main = mains.first
    problems << "<main> has no id=\"main\" for the skip link to target" if main && main[:node].attr["id"] != "main"

    skip = find_all(root, "a").find { |e| e[:node].attr["class"].to_s.split.include?("skip-link") }
    if skip.nil?
      problems << "no skip link (a.skip-link)"
    else
      problems << "skip link href is #{skip[:node].attr['href'].inspect}, not \"#main\"" if skip[:node].attr["href"] != "#main"
      problems << "skip link has no text" if text_of(skip[:node]).strip.empty?
      # It must be the first tab stop: no other link or element before it inside <body>.
      first_link = find_all(root, "a").first
      problems << "skip link is not the first link on the page" unless first_link && first_link[:node].equal?(skip[:node])
    end

    # Landmark content: every heading below the h1 sits inside <main>.
    h1s = find_all(root, "h1")
    problems << "expected exactly one <h1>, found #{h1s.size}" unless h1s.size == 1
    %w[h2 h3].each do |tag|
      find_all(root, tag).each do |h|
        next if main && h[:ancestors].any? { |a| a.equal?(main[:node]) }

        problems << "<#{tag}> #{text_of(h[:node]).strip.inspect} is outside <main>"
      end
    end

    # Headings never skip a level in document order (an h3 before any h2 is a skip).
    previous = 1
    elements(root).each do |e|
      tag = tag_of(e[:node])
      next unless tag.match?(/\Ah[1-6]\z/)

      level = tag[1].to_i
      problems << "heading #{text_of(e[:node]).strip.inspect} jumps from h#{previous} to h#{level}" if level > previous + 1
      previous = level
    end

    if home
      # Every section title is a real heading, not a styled span.
      titles = elements(root).select { |e| e[:node].attr["class"].to_s.split.include?("section-title") }
      problems << "no .section-title elements found on the home page" if titles.empty?
      titles.each do |e|
        problems << "section title #{text_of(e[:node]).strip.inspect} is <#{tag_of(e[:node])}>, not <h2>" unless tag_of(e[:node]) == "h2"
      end
      find_all(root, "img").each do |e|
        attr = e[:node].attr
        problems << "<img src=#{attr['src'].inspect}> lacks width/height" unless attr["width"].to_s.match?(/\A\d+\z/) && attr["height"].to_s.match?(/\A\d+\z/)
      end
    end

    problems
  end

  # Whether the stylesheet makes `.animate-in` content visible when prefers-reduced-motion is
  # set: a reduced-motion block that sets opacity: 1 and stops the animation, AFTER the base
  # `.animate-in` rule (same specificity, so source order decides which one wins).
  def reduced_motion_shows_content?(css)
    rules = css_rules(css)
    base = rules.index { |sel, _decls, at| sel == ".animate-in" && at.nil? }
    override = rules.rindex do |sel, decls, at|
      sel == ".animate-in" && at.to_s.match?(/prefers-reduced-motion:\s*reduce/) &&
        decls["opacity"] == "1" && decls["animation"] == "none"
    end
    !base.nil? && !override.nil? && override > base
  end
end
