source "https://rubygems.org"
gem "jekyll", "~> 4.3"
gem "webrick"

group :jekyll_plugins do
  # Pinned to the cms-platform v0.1.0 release tag — kept in lockstep with
  # platform.lock (platform_ref) and the @v0.1.0 pins on the .github thin
  # callers. Dependabot's bundler ecosystem bumps this tag when the platform
  # tags a new release.
  gem "cms-platform-theme", git: "https://github.com/Adam-S-Daniel/cms-platform", glob: "theme/*.gemspec", tag: "v0.1.3"
end
