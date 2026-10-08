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
  gem "cms-platform-theme", git: "https://github.com/Adam-S-Daniel/cms-platform", glob: "theme/*.gemspec", ref: "0ba7e28bbf9e2a25635c4f245ea38d2f9c711587"
end
