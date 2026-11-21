# Homebrew formula for hello-node (from shipcrate). Lives at Formula/hello-node.rb in you/homebrew-hello-node;
# scripts/release.sh rewrites the version and sha256 lines on every release.
class HelloNode < Formula
  desc "A tiny Node CLI showing shipcrate releases and updates"
  homepage "https://github.com/you/hello-node"
  version "0.0.0"
  url "https://github.com/you/hello-node/releases/download/v#{version}/hello-node.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # shipcrate:any
  license "MIT"

  def install
    bin.install "hello-node"
  end

  test do
    system bin/"hello-node", "--version"
  end
end
