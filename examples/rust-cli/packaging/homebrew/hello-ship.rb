# Homebrew formula for hello-ship (from shipcrate). Lives at Formula/hello-ship.rb in you/homebrew-hello-ship;
# scripts/release.sh rewrites the version and sha256 lines on every release.
class HelloShip < Formula
  desc "A tiny CLI showing shipcrate releases and updates"
  homepage "https://github.com/you/hello-ship"
  version "0.0.0"
  on_macos do
    on_arm do
      url "https://github.com/you/hello-ship/releases/download/v#{version}/hello-ship-macos-arm64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000" # shipcrate:macos-arm64
    end
    on_intel do
      url "https://github.com/you/hello-ship/releases/download/v#{version}/hello-ship-macos-x64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000" # shipcrate:macos-x64
    end
  end
  on_linux do
    on_intel do
      url "https://github.com/you/hello-ship/releases/download/v#{version}/hello-ship-linux-x64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000" # shipcrate:linux-x64
    end
    on_arm do
      url "https://github.com/you/hello-ship/releases/download/v#{version}/hello-ship-linux-arm64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000" # shipcrate:linux-arm64
    end
  end
  license "MIT"

  def install
    bin.install "hello-ship"
  end

  test do
    system bin/"hello-ship", "--version"
  end
end
