# Homebrew formula for {{PRODUCT}} (from shipcrate). Lives at {{TAP_FILE}} in {{TAP_REPO}};
# scripts/release.sh rewrites the version and sha256 lines on every release.
class {{CLASS}} < Formula
  desc "{{DESCRIPTION}}"
  homepage "https://github.com/{{REPO}}"
  version "0.0.0"
  #SHIPCRATE_URLS
  license "MIT"

  def install
    bin.install "{{BINARY}}"
  end

  test do
    system bin/"{{BINARY}}", "--version"
  end
end
