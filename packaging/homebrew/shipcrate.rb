# Homebrew formula for shipcrate itself. Lives at Formula/shipcrate.rb in simarpreetsingh-019/homebrew-shipcrate.
# Bump: version + sha256 of the tag's source tarball (tools/bump-formula.sh does it).
class Shipcrate < Formula
  desc "Release and update tooling in one command: gate, checksums, provenance, Homebrew, updates"
  homepage "https://simarpreetsingh-019.github.io/shipcrate/"
  url "https://github.com/simarpreetsingh-019/shipcrate/archive/refs/tags/v0.5.1.tar.gz"
  sha256 "16ff9c491e0e692f95a9803f38e45d875c6177a2261382a1987d8ae626377960"
  license "MIT"

  depends_on "gh"

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"bin/shipcrate"
  end

  test do
    assert_match "shipcrate", shell_output("#{bin}/shipcrate version")
  end
end
