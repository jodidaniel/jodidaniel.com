# frozen_string_literal: true

require "yaml"
require "date"

# What the home page's `Person` JSON-LD (_includes/home-seo.html) must say for a
# given source tree, derived from the same files in plain Ruby. Shared by
# scripts/verify-build-artifacts.rb and scripts/test-person-rules.rb so the two
# agree on one definition, and so an ordinary /admin edit (a changed Contact
# link, a lowercase "present", no current job) is something the verifier derives
# its expectation from rather than a fact it hardcodes.
module PersonRules
  module_function

  def read(path)
    File.exist?(path) ? File.read(path, encoding: "utf-8") : ""
  end

  def data(root, name)
    YAML.safe_load(read(File.join(root, "_data", name)), permitted_classes: [Date, Time]) || {}
  end

  # Front matter of every `<root>/<dir>/*.md`, ordered by weight like Liquid's
  # `sort: "weight"`. Equal weights have no guaranteed order there, so content
  # gives every item its own weight; ties here fall back to file name.
  #
  # A missing or null `title:` is not blank to Jekyll: it fills one in from the
  # file name ("2-health-data-privacy.md" -> "2 Health Data Privacy", Jekyll's
  # Document#populate_title), and the page emits that, so this does too. Only an
  # explicit empty string stays empty.
  def items(root, dir)
    Dir[File.join(root, dir, "*.md")].sort.map do |f|
      m = read(f).match(/\A---\s*\n(.*?)\n---/m)
      fm = m && YAML.safe_load(m[1], permitted_classes: [Date, Time])
      fm["title"] ||= File.basename(f, ".*").split("-").map(&:capitalize).join(" ") if fm.is_a?(Hash)
      fm
    end.compact.each_with_index.sort_by { |fm, i| [fm["weight"].to_i, i] }.map(&:first)
  end

  def present(value)
    !value.to_s.empty?
  end

  # First Experience item whose period contains "present", any case; nil if none.
  def current_job(root)
    items(root, "_experience").find { |fm| fm["period"].to_s.downcase.include?("present") }
  end

  # The fields the Person must carry; a key is absent from the hash when the
  # source has nothing for it, mirroring the template's omissions.
  def expected(root)
    settings = data(root, "settings.yml")
    out = {}
    job = current_job(root)
    out["jobTitle"] = job["title"] if job && present(job["title"])
    out["worksFor"] = job["org"] if job && present(job["org"])
    schools = items(root, "_education").map { |fm| fm["school"] }.select { |v| present(v) }
    out["alumniOf"] = schools unless schools.empty?
    areas = items(root, "_expertise").map { |fm| fm["title"] }.select { |v| present(v) }
    out["knowsAbout"] = areas unless areas.empty?
    urls = data(root, "contact.yml")["links"].to_a.map { |l| l["url"] } + settings.dig("share", "profile_links").to_a
    same_as = urls.select { |u| u.to_s.include?("https://") }.uniq
    out["sameAs"] = same_as unless same_as.empty?
    names = settings.dig("share", "alternate_names").to_a
    out["alternateName"] = names unless names.empty?
    out
  end

  # The same hash read back from a built Person object.
  def observed(person)
    out = {}
    out["jobTitle"] = person["jobTitle"] if person.key?("jobTitle")
    out["worksFor"] = person.dig("worksFor", "name") if person.key?("worksFor")
    out["alumniOf"] = person["alumniOf"].map { |o| o["name"] } if person.key?("alumniOf")
    %w[knowsAbout sameAs alternateName].each { |k| out[k] = person[k] if person.key?(k) }
    out
  end
end
