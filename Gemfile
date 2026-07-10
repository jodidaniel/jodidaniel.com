source "https://rubygems.org"
gem "jekyll", "~> 4.3"
gem "webrick"

group :jekyll_plugins do
  # Pinned to the cms-platform release tag below (see `tag:`) — kept in lockstep
  # with platform.lock (platform_ref) and the `@`-tag `uses:` pins on the .github
  # thin callers. Dependabot's bundler ecosystem bumps this tag when the platform
  # tags a new release.
  gem "cms-platform-theme", git: "https://github.com/Adam-S-Daniel/cms-platform", glob: "theme/*.gemspec", tag: "v0.1.61"
end
