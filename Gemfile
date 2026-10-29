source "https://rubygems.org"
gem "jekyll", "~> 4.3"
gem "webrick"

group :jekyll_plugins do
  # Pinned to the cms-platform release tag below (see `tag:`) — kept in lockstep
  # with platform.lock (platform_ref) and the `@`-tag `uses:` pins on the .github
  # thin callers. platform-bump.yml bumps this tag — atomically, together with
  # platform.lock and the uses: pins — when the platform tags a new release;
  # Dependabot is set to ignore this gem (see .github/dependabot.yml,
  # cms-platform#242).
  gem "cms-platform-theme", git: "https://github.com/Adam-S-Daniel/cms-platform", glob: "theme/*.gemspec", ref: "5fdff7cb5ca3b3b035517d5c069f1a3ba4ac7795"
end
