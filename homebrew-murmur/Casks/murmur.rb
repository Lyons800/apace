cask "murmur" do
  version "1.0.0"
  sha256 "REPLACE_WITH_DMG_SHA256"

  url "https://github.com/oisinlyons/murmur/releases/download/v#{version}/Murmur.dmg"
  name "Murmur"
  desc "On-device voice-to-text for macOS — hold a key, speak, release"
  homepage "https://murmur.dev"

  depends_on macos: ">= :sonoma"

  app "Murmur.app"

  zap trash: [
    "~/Library/Application Support/Murmur",
    "~/Library/Preferences/dev.murmur.app.plist",
    "~/Library/Caches/dev.murmur.app",
  ]
end
