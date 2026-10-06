#!/usr/bin/env ruby
# frozen_string_literal: true

# Builds the site with the gate open and an ordinary /admin edit applied, then
# checks the home page's Person JSON-LD (_includes/home-seo.html) against EXPLICIT
# values and against scripts/person_rules.rb, which scripts/verify-build-artifacts.rb
# uses. The point: the edits Jodi makes herself must neither break the Person data
# nor make the verifier (a required check on her CMS PRs) expect something the
# build cannot say.
#
#   ruby scripts/test-person-rules.rb
#
# Each scenario copies the tracked source into a temp dir outside the repo (no
# .git, so nothing run there can reach origin), edits it there only, and builds.

require "minitest/autorun"
require "json"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require_relative "person_rules"

class PersonRulesTest < Minitest::Test
  REPO_ROOT = File.expand_path("..", __dir__)

  def build_with
    Dir.mktmpdir("person-rules-") do |tmp|
      src = File.join(tmp, "src")
      tracked, status = Open3.capture2("git", "-C", REPO_ROOT, "ls-files", "-z")
      assert status.success?, "git ls-files failed"
      tracked.split("\0").each do |rel|
        next unless File.file?(File.join(REPO_ROOT, rel))
        FileUtils.mkdir_p(File.dirname(File.join(src, rel)))
        FileUtils.cp(File.join(REPO_ROOT, rel), File.join(src, rel))
      end
      edit = ->(rel, &blk) do
        path = File.join(src, rel)
        before = File.read(path, encoding: "utf-8")
        after = blk.call(before)
        refute_equal before, after, "scenario edit to #{rel} changed nothing"
        File.write(path, after)
      end
      edit.call("_data/settings.yml") { |t| t.sub(/^site_live: false/, "site_live: true") }
      yield src, edit
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

  def test_unedited_site
    person = build_with { |_src, _edit| }
    assert_equal "Partner", person["jobTitle"]
    assert_equal "Wilson Sonsini Goodrich & Rosati", person.dig("worksFor", "name")
    assert_includes person["sameAs"], "https://www.linkedin.com/in/jodidaniel/"
  end

  # She changes her firm link in Contact: sameAs follows it, and no check names a host.
  def test_changed_contact_firm_url
    new_url = "https://www.example.com/people/jodi-daniel-new.html"
    person = build_with do |_src, edit|
      edit.call("_data/contact.yml") { |t| t.sub("https://www.wsgr.com/en/people/jodi-daniel.html", new_url) }
    end
    assert_includes person["sameAs"], new_url
    refute_includes person["sameAs"].join(" "), "wsgr.com"
  end

  # "present" in any case still marks the current job.
  def test_lowercase_present_still_current
    person = build_with do |_src, edit|
      edit.call("_experience/1-wilson-sonsini.md") { |t| t.sub('period: "2025 - Present"', 'period: "2025 - present"') }
    end
    assert_equal "Partner", person["jobTitle"]
    assert_equal "Wilson Sonsini Goodrich & Rosati", person.dig("worksFor", "name")
  end

  # No item says "present": no jobTitle or worksFor, and nothing else breaks.
  def test_no_current_job
    person = build_with do |_src, edit|
      edit.call("_experience/1-wilson-sonsini.md") { |t| t.sub('period: "2025 - Present"', 'period: "2025 - 2026"') }
    end
    refute person.key?("jobTitle")
    refute person.key?("worksFor")
    assert_equal "Jodi Daniel", person["name"]
    assert person["alumniOf"].size.positive?
  end
end
