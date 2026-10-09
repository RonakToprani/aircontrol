cask "aircontrol" do
  version "0.4.1"
  sha256 "fec1d47a49caf8a3b5736fca585a45dd39503a1b52d660373fce10222268e9f9"

  url "https://github.com/RonakToprani/aircontrol/releases/download/v#{version}/AirControl-#{version}.dmg"
  name "AirControl"
  desc "Control your Mac with in-air hand gestures from the webcam — fully on-device"
  homepage "https://github.com/RonakToprani/aircontrol"

  depends_on macos: ">= :sonoma"

  app "AirControl.app"

  caveats <<~EOS
    AirControl is not notarized — install with the quarantine flag skipped:

      brew install --cask --no-quarantine aircontrol

    First run: click the hand icon in the menu bar → Enable AirControl,
    allow Camera access, and flip the AirControl switch in
    System Settings → Privacy & Security → Accessibility (the prompt only
    opens the page). Then run "Calibrate hand range…" from the menu.

    Everything runs on-device. Nothing is recorded or sent anywhere.
  EOS

  zap trash: [
    "~/Library/Preferences/com.ronaktoprani.aircontrol.plist",
  ]
end
