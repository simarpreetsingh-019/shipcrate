# Homebrew formula for hello-py (from shipcrate). Lives at Formula/hello-py.rb in you/homebrew-hello-py;
# scripts/release.sh rewrites the version and sha256 lines on every release.
class HelloPy < Formula
  desc "A tiny Python CLI showing shipcrate releases and updates"
  homepage "https://github.com/you/hello-py"
  version "0.0.0"
  url "https://github.com/you/hello-py/releases/download/v#{version}/hello-py.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # shipcrate:any
  license "MIT"

  def install
    bin.install "hello-py"
  end

  test do
    system bin/"hello-py", "--version"
  end
end
