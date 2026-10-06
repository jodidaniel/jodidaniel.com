#!/usr/bin/env ruby
# frozen_string_literal: true

# Copy-consistency checks on the content files (jodidaniel/jodidaniel.com#26 copy nits).
# No build, no network:
#
#   ruby scripts/test-content-copy.rb
#
# House style these pin:
#   * "D.C." with periods, matching "U.S.", "J.D.", "M.P.H.", "B.A." elsewhere in the copy.
#   * Year ranges and "Present" use an en dash, no spaces ("2015–2025"), not a hyphen.
#   * Titles read "Must Be", not "Must be", in title case.
#   * Each Writing/Talks/Press category lists newest first (lowest `weight` = newest).
#
# `_events/` is deliberately NOT scanned: events are ordered by `start_date`, and their
# copy is owned by the past-events work.

require "minitest/autorun"
require "yaml"
require "date"

class ContentCopyTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCANNED_DIRS = %w[_data _experience _media _accomplishments _expertise _education].freeze
  MONTHS = Date::MONTHNAMES.compact.freeze

  def self.front_matter(path)
    parts = File.read(path, encoding: "utf-8").split(/^---\s*$/, 3)
    return nil if parts.length < 3

    YAML.safe_load(parts[1], aliases: true, permitted_classes: [Date, Time])
  end

  def item_files(dir)
    Dir.glob(File.join(ROOT, dir, "*.md")).sort
  end

  # Every string value in the scanned content, with where it came from.
  def each_string(node, label, &blk)
    case node
    when String then blk.call(label, node)
    when Hash then node.each { |k, v| each_string(v, "#{label}.#{k}", &blk) }
    when Array then node.each_with_index { |v, i| each_string(v, "#{label}[#{i}]", &blk) }
    end
  end

  def scanned_strings
    out = []
    SCANNED_DIRS.each do |dir|
      Dir.glob(File.join(ROOT, dir, "*.{md,yml}")).sort.each do |path|
        data = path.end_with?(".yml") ? YAML.safe_load_file(path, aliases: true) : self.class.front_matter(path)
        each_string(data, File.join(dir, File.basename(path)), &->(l, s) { out << [l, s] })
      end
    end
    out
  end

  def test_washington_dc_uses_periods
    bad = scanned_strings.select { |_, s| s.match?(/\bDC\b/) }
    assert_empty bad.map(&:first), 'write "Washington, D.C." (with periods), the form the rest of the copy uses'
  end

  def test_experience_periods_use_en_dash_without_spaces
    item_files("_experience").each do |path|
      period = self.class.front_matter(path)["period"].to_s
      refute_match(/\s-\s|\d-\d|-Present/, period, "#{File.basename(path)} period #{period.inspect} needs an en dash")
      if period.match?(/\d{4}.\d|Present/)
        assert_match(/\A\d{4}–(\d{4}|Present)\z/, period, "#{File.basename(path)} period #{period.inspect}")
      end
    end
  end

  def test_titles_say_must_be
    bad = scanned_strings.select { |l, s| l.include?(".title") && s.match?(/\b[Mm]ust be\b/) && !s.match?(/\bMust Be\b/) }
    assert_empty bad.map(&:first), 'title case is "Must Be"'
  end

  # "April 2025" -> [2025, 4]; "2024" -> [2024, nil]; blank or "Ongoing" -> nil (not comparable).
  def sort_key(date_display)
    s = date_display.to_s.strip
    return [Regexp.last_match(1).to_i, nil] if s =~ /\A(\d{4})\z/

    m = s.match(/\A(#{MONTHS.join('|')}) (\d{4})\z/)
    m ? [m[2].to_i, MONTHS.index(m[1]) + 1] : nil
  end

  # True when `a` is strictly older than `b`; a bare year is only compared on the year.
  def older?(a, b)
    return a[0] < b[0] if a[0] != b[0]
    return false if a[1].nil? || b[1].nil?

    a[1] < b[1]
  end

  def test_media_lists_newest_first_within_each_category
    items = item_files("_media").map { |p| [File.basename(p), self.class.front_matter(p)] }
    items.group_by { |_, fm| fm["category"] }.each do |category, group|
      dated = group.sort_by { |_, fm| fm["weight"] }
                   .map { |name, fm| [name, sort_key(fm["date_display"])] }
                   .reject { |_, key| key.nil? }
      dated.each_cons(2) do |(name_a, a), (name_b, b)|
        refute older?(a, b), "#{category}: #{name_a} (#{a.inspect}) is listed before the newer #{name_b} (#{b.inspect})"
      end
    end
  end
end
