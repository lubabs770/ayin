cask "iris" do
  version "0.4.0"
  sha256 "9b281ddeec6e30ae490a0190883be6d575c41055d2f13cea91a4994c5ecc60ea"

  url "https://github.com/lubabs770/ayin/releases/download/v#{version}/Iris-v#{version}.zip"
  name "Iris"
  desc "Floating webcam viewing window (a hand mirror)"
  homepage "https://github.com/lubabs770/ayin"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true

  app "Iris.app"

  caveats <<~EOS
    Iris is not signed with an Apple Developer certificate.
    macOS will show a warning about an unsigned application on first launch.

    To allow Iris to run:
      1. Right-click (or Control-click) on Iris.app and select "Open"
      2. Click "Open" in the security dialog
      3. If that doesn't work, go to System Settings > Privacy & Security
         and look for an option to allow Iris under the "Security" section
  EOS

  zap trash: [
    "~/Library/Preferences/com.iris.app.plist",
  ]
end
