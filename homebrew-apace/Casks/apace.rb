cask "apace" do
  version "1.1.0"
  sha256 :no_check

  url "https://github.com/Lyons800/apace/releases/download/v#{version}/Apace.dmg"
  name "Apace"
  desc "On-device voice-to-text for macOS — hold a key, speak, release"
  homepage "https://apace.so"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "Apace.app"

  zap trash: [
    "~/Library/Application Support/Apace",
    "~/Library/Preferences/so.apace.plist",
    "~/Library/Caches/so.apace",
  ]
end
