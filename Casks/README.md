# Homebrew cask

`aircontrol.rb` is the cask for a future tap repo. To publish it:

1. Create a public repo named `RonakToprani/homebrew-tap`.
2. Copy this `Casks/` directory into it.
3. Users then install with:

   ```bash
   brew install --cask --no-quarantine RonakToprani/tap/aircontrol
   ```

   (`--no-quarantine` because the app isn't notarized; without it, Homebrew
   applies the quarantine flag and Gatekeeper blocks the unsigned app.)

On each release: bump `version`, and update `sha256` with the value from
`dist/checksums.txt` (emitted by `make dist`).
