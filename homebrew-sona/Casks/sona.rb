cask "sona" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/Lyons800/sona/releases/download/v#{version}/Sona.dmg"
  name "Sona"
  desc "On-device voice-to-text for macOS — hold a key, speak, release"
  homepage "https://sona.app"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "Sona.app"

  zap trash: [
    "~/Library/Application Support/Sona",
    "~/Library/Preferences/app.sona.plist",
    "~/Library/Caches/app.sona",
  ]
end
