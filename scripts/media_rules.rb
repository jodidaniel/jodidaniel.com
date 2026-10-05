# frozen_string_literal: true

# Rules scripts/verify-build-artifacts.rb applies to `_media/*.md` entries, kept in a
# file of their own so scripts/test-media-rules.rb can test them without a Jekyll build.
# `scripts/` is excluded from the Jekyll build (_config.yml), so this is never published.

module MediaRules
  # Month YYYY, a bare year, or "Ongoing" -- the shapes the owner may type in /admin.
  DATE_DISPLAY_RE = /\A(Ongoing|(January|February|March|April|May|June|July|August|September|October|November|December) \d{4}|\d{4})\z/

  # Jekyll's default slugify pattern (jekyll 4.4.1, Jekyll::Utils::SLUGIFY_DEFAULT_REGEXP).
  SLUGIFY_FALLBACK_RE = /[^\p{M}\p{L}\p{Nd}]+/

  module_function

  # The value of an optional text field, "" when the key is absent. Decap writes NO key
  # for an optional text field left blank (issue #338), so absent must mean empty.
  def optional_text(front_matter, key)
    front_matter[key].to_s
  end

  # nil when `date_display` is acceptable, else a short reason. Absent and empty are both
  # fine: the form labels the field "(optional)".
  def date_display_problem(front_matter)
    value = optional_text(front_matter, "date_display")
    return nil if value.empty? || value.match?(DATE_DISPLAY_RE)

    "date_display #{value.inspect} is not Month YYYY, a bare year, or \"Ongoing\""
  end

  # The `:slug` Jekyll puts in `/media/:slug/` for a `_media/<name>.md` file. Uses Jekyll's
  # own slugify when it can be loaded; otherwise an equivalent (the test compares the two
  # whenever Jekyll is installed). Characters such as an em dash are dropped, so the built
  # page is NOT at the raw file name (issue #339).
  # A `slug:` in the front matter wins over the file name, exactly as in Jekyll's UrlDrop
  # (pass the parsed front matter Hash as `front_matter`).
  def page_slug(source_path, front_matter = nil)
    override = front_matter.is_a?(Hash) ? front_matter["slug"] : nil
    name = override.nil? ? File.basename(source_path, ".md") : override.to_s
    begin
      require "jekyll"
      Jekyll::Utils.slugify(name)
    rescue LoadError
      fallback_slug(name)
    end
  end

  # Jekyll default-mode slugify without Jekyll: runs of non-letters/digits become "-",
  # leading/trailing "-" are stripped, then lower-cased.
  def fallback_slug(name)
    name.gsub(SLUGIFY_FALLBACK_RE, "-").gsub(/\A-+|-+\z/, "").downcase
  end

  # Where the built page for a `_media` source file lives under the built site `site_dir`.
  def page_path(site_dir, source_path, front_matter = nil)
    File.join(site_dir, "media", page_slug(source_path, front_matter), "index.html")
  end
end
