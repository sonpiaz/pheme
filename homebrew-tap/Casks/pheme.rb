cask "pheme" do
  version "0.1.0"
  sha256 :no_check # TODO: Update with actual SHA256 after first release

  url "https://github.com/sonpiaz/pheme/releases/download/v#{version}/Pheme-#{version}.dmg"
  name "Pheme"
  desc "AI meeting notes for macOS, optimized for Vietnamese"
  homepage "https://github.com/sonpiaz/pheme"

  depends_on macos: ">= :sonoma" # macOS 14.2+

  app "Pheme.app"

  zap trash: [
    "~/Library/Application Support/Pheme",
    "~/Library/Logs/Pheme",
    "~/Library/Preferences/com.sonpiaz.pheme.plist",
    "~/Library/Saved Application State/com.sonpiaz.pheme.savedState",
  ]
end
