# Homebrew cask for HelloShip (from shipcrate). Lives at Casks/helloship.rb in you/homebrew-helloship;
# scripts/release.sh rewrites the version and sha256 lines on every release.
cask "helloship" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # shipcrate:macos

  url "https://github.com/you/HelloShip/releases/download/v#{version}/HelloShip.zip"
  name "HelloShip"
  desc "A tiny Mac app showing shipcrate in-app updates"
  homepage "https://github.com/you/HelloShip"

  # The app updates itself; tell Homebrew so `brew upgrade` doesn't fight it.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "HelloShip.app"

  zap trash: [
    "~/Library/Preferences/com.example.helloship.plist",
    "~/Library/Caches/com.example.helloship",
  ]
end
