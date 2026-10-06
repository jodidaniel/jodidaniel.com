# frozen_string_literal: true

# Accessibility rules (WCAG 2.2 AA) scripts/verify-build-artifacts.rb applies to the stylesheet
# and to the built pages, in a file of their own so scripts/test-a11y-rules.rb can test them
# without a Jekyll build. `scripts/` is excluded from the Jekyll build (_config.yml), so this
# is never published.
#
# Built pages are read with kramdown's HTML parser (a Jekyll dependency, so already installed),
# not a regex: what matters is where an element sits, and a regex cannot see nesting.

begin
  require "kramdown"
rescue LoadError
  require "bundler/setup"
  require "kramdown"
end

module A11yRules
  # Body text must reach 4.5:1 (WCAG 1.4.3). These are the light surfaces text sits on in
  # assets/css/jodidaniel.css: the white card, the #f8fafc item background and the #e8f4f8 hover
  # background. The worst case is the darkest of them.
  LIGHT_SURFACES = %w[#ffffff #f8fafc #e8f4f8].freeze
  MIN_RATIO = 4.5

  # Rules whose text sits on the page's gradient, not on a card. axe cannot compute a contrast
  # over a gradient (it reports "incomplete"), so these are checked in a browser, not here.
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
