# Homebrew formula for {{PRODUCT}} (from shipcrate). Lives at {{TAP_FILE}} in {{TAP_REPO}};
# scripts/release.sh rewrites the version and sha256 lines on every release.
class {{CLASS}} < Formula
  desc "{{DESCRIPTION}}"
  homepage "https://github.com/{{REPO}}"
  version "0.0.0"
  url "https://github.com/{{REPO}}/releases/download/v#{version}/{{ASSET}}"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  def install
    bin.install "{{BINARY}}"
  end

  test do
    system bin/"{{BINARY}}", "--version"
  end
end
