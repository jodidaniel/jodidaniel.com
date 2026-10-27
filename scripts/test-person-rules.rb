#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds the site with the gate open over FIXED fixture content (invented
# placeholder names and example.com / example.net links, never her real
# profile) and checks the home page's Person JSON-LD (_includes/home-seo.html)
# against EXPLICIT values and against scripts/person_rules.rb, which
# scripts/verify-build-artifacts.rb uses.
#
# Why fixtures and not the live content: this test runs inside the required
# site-verify check, so a test that read what she has published would go red on
# the very /admin edits it exists to tolerate (a changed link, a new current
# job, `site_live: true` at launch). Layouts, plugins and the theme config are
# still the repo's own; only the content the Person reads is replaced.
#
#   ruby scripts/test-person-rules.rb
#
# Each scenario copies the tracked source into a temp dir outside the repo (no
# .git, so nothing run there can reach origin), swaps in the fixtures, edits
# them there only, and builds.

require "minitest/autorun"
require "json"
require "yaml"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "person_rules"

class PersonRulesTest < Minitest::Test
  REPO_ROOT = File.expand_path("..", __dir__)
  CONTENT_DIRS = %w[_experience _education _expertise].freeze
  FIRM_URL = "https://www.example.com/people/pat-placeholder.html"

  # The content the Person reads, as path => text. `site_live` and `header.yml`
  # are overridden in the copy of the live files (they carry keys the layouts
  # need that no scenario cares about).
  def fixture_files
    {
      "_experience/1-acme.md" => "---\ntitle: \"Partner\"\norg: \"Example Firm LLP\"\nperiod: \"2025 - Present\"\nweight: 1\n---\n",
      "_experience/2-sample.md" => "---\ntitle: \"Counsel\"\norg: \"Sample Agency\"\nperiod: \"2019 - 2024\"\nweight: 2\n---\n",
      "_education/1-law.md" => "---\ndegree: \"J.D.\"\nschool: \"Example University School of Law\"\nweight: 1\n---\n",
      "_education/2-college.md" => "---\ndegree: \"B.A.\"\nschool: \"Sample College\"\nweight: 2\n---\n",
      "_expertise/1-area-one.md" => "---\ntitle: \"Area One\"\ndescription: \"Placeholder text.\"\nweight: 1\n---\n",
      "_expertise/2-area-two.md" => "---\ntitle: \"Area Two\"\ndescription: \"Placeholder text.\"\nweight: 2\n---\n",
      "_data/contact.yml" => <<~YAML
        heading: "Connect"
        intro: "Placeholder intro."
        links:
          - { label: "Firm Profile", url: "#{FIRM_URL}", icon: "globe" }
          - { label: "LinkedIn",     url: "https://www.example.net/in/pat-placeholder/", icon: "linkedin" }
      YAML
    }
  end

  def fixture_share
    { "alternate_names" => ["Pat Q. Placeholder"], "profile_links" => ["https://www.example.net/profile/pat-placeholder/"] }
  end

  def change(files, rel, from, to)
    before = files.fetch(rel)
    after = before.sub(from, to)
    refute_equal before, after, "scenario edit to #{rel} changed nothing"
    files[rel] = after
  end

  def build_with
    Dir.mktmpdir("person-rules-") do |tmp|
      src = File.join(tmp, "src")
      tracked, status = Open3.capture2("git", "-C", REPO_ROOT, "ls-files", "-z")
      assert status.success?, "git ls-files failed"
      tracked.split("\0").each do |rel|
        next unless File.file?(File.join(REPO_ROOT, rel))
        next if CONTENT_DIRS.any? { |dir| rel.start_with?("#{dir}/") }
        FileUtils.mkdir_p(File.dirname(File.join(src, rel)))
        FileUtils.cp(File.join(REPO_ROOT, rel), File.join(src, rel))
      end

      files = fixture_files
      settings = { "site_live" => true, "share" => fixture_share }
      yield files, settings

      settings_path = File.join(src, "_data", "settings.yml")
      live_settings = YAML.safe_load(File.read(settings_path, encoding: "utf-8")) || {}
      File.write(settings_path, YAML.dump(live_settings.merge(settings)))
      header_path = File.join(src, "_data", "header.yml")
      live_header = YAML.safe_load(File.read(header_path, encoding: "utf-8")) || {}
      File.write(header_path, YAML.dump(live_header.merge("name" => "Pat Placeholder")))
      files.each do |rel, text|
        FileUtils.mkdir_p(File.dirname(File.join(src, rel)))
        File.write(File.join(src, rel), text)
      end

      site = File.join(tmp, "site")
      out, status = Open3.capture2e({ "JEKYLL_ENV" => "production" }, "bundle", "exec", "jekyll", "build", "--quiet",
                                    "--source", src, "--destination", site, chdir: REPO_ROOT)
      assert status.success?, "jekyll build failed:\n#{out}"
      html = File.read(File.join(site, "index.html"), encoding: "utf-8")
      raws = html.scan(%r{<script type="application/ld\+json">(.*?)</script>}m).flatten
      person = raws.map { |r| JSON.parse(r) }.find { |b| b["@type"] == "Person" }
      refute_nil person, "no Person JSON-LD on the open home page"
      # The verifier's expectation must equal what was built, in every scenario.
      assert_equal PersonRules.expected(src), PersonRules.observed(person)
      person
    end
  end

  def test_fixture_site
    person = build_with { |_files, _settings| }
    assert_equal "Pat Placeholder", person["name"]
    assert_equal "Partner", person["jobTitle"]
    assert_equal "Example Firm LLP", person.dig("worksFor", "name")
    assert_equal ["Example University School of Law", "Sample College"], person["alumniOf"].map { |o| o["name"] }
    assert_equal ["Area One", "Area Two"], person["knowsAbout"]
    assert_equal [FIRM_URL, "https://www.example.net/in/pat-placeholder/", "https://www.example.net/profile/pat-placeholder/"],
                 person["sameAs"]
    assert_equal ["Pat Q. Placeholder"], person["alternateName"]
  end

  # She changes her firm link in Contact: sameAs follows it, and no check names a host.
  def test_changed_contact_firm_url
    new_url = "https://www.example.com/people/pat-placeholder-new.html"
    person = build_with { |files, _settings| change(files, "_data/contact.yml", FIRM_URL, new_url) }
    assert_includes person["sameAs"], new_url
    refute_includes person["sameAs"], FIRM_URL
  end

  # "present" in any case still marks the current job.
  def test_lowercase_present_still_current
    person = build_with { |files, _settings| change(files, "_experience/1-acme.md", "2025 - Present", "2025 - present") }
    assert_equal "Partner", person["jobTitle"]
    assert_equal "Example Firm LLP", person.dig("worksFor", "name")
  end

  # No item says "present": no jobTitle or worksFor, and nothing else breaks.
  def test_no_current_job
    person = build_with { |files, _settings| change(files, "_experience/1-acme.md", "2025 - Present", "2025 - 2026") }
    refute person.key?("jobTitle")
    refute person.key?("worksFor")
    assert_equal "Pat Placeholder", person["name"]
    assert person["alumniOf"].size.positive?
  end

  # A new "present" job that sorts first becomes the current role.
  def test_new_current_job_added
    person = build_with do |files, _settings|
      files["_experience/0-newest.md"] = "---\ntitle: \"Chair\"\norg: \"Another Example Org\"\nperiod: \"2026 - present\"\nweight: 0\n---\n"
    end
    assert_equal "Chair", person["jobTitle"]
    assert_equal "Another Example Org", person.dig("worksFor", "name")
  end

  # A blank title is skipped, never emitted as an empty string or null.
  def test_blank_expertise_title_is_skipped
    person = build_with { |files, _settings| change(files, "_expertise/2-area-two.md", 'title: "Area Two"', 'title: ""') }
    assert_equal ["Area One"], person["knowsAbout"]
  end

  # A null `title:` is NOT blank to Jekyll: it infers one from the file name
  # ("2-area-two.md" -> "2 Area Two") and the page emits it, so the expectation
  # must say the same.
  def test_null_expertise_title_is_inferred_from_the_file_name
    person = build_with { |files, _settings| change(files, "_expertise/2-area-two.md", 'title: "Area Two"', "title:") }
    assert_equal ["Area One", "2 Area Two"], person["knowsAbout"]
  end

  def test_null_job_title_is_inferred_from_the_file_name
    person = build_with { |files, _settings| change(files, "_experience/1-acme.md", 'title: "Partner"', "title:") }
    assert_equal "1 Acme", person["jobTitle"]
  end
end
