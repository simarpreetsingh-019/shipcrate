# Homebrew cask for {{PRODUCT}} (from shipcrate). Lives at {{TAP_FILE}} in {{TAP_REPO}};
# scripts/release.sh rewrites the version and sha256 lines on every release.
cask "{{TOKEN}}" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # shipcrate:macos

  url "https://github.com/{{REPO}}/releases/download/v#{version}/{{ASSET}}"
  name "{{PRODUCT}}"
  desc "{{DESCRIPTION}}"
  homepage "https://github.com/{{REPO}}"

  # The app updates itself; tell Homebrew so `brew upgrade` doesn't fight it.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "{{PRODUCT}}.app"

  zap trash: [
    "~/Library/Preferences/{{BUNDLE_ID}}.plist",
    "~/Library/Caches/{{BUNDLE_ID}}",
  ]
end
