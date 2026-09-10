<p align="center">
  <img src="docs/images/icon.png" alt="Hugging Face for macOS app icon" width="144">
</p>

<h1 align="center">Hugging Face for macOS</h1>

<p align="center">
  A native menu bar companion for keeping an eye on Hugging Face Jobs, Inference Endpoints, and usage.
</p>

## Features

- Monitor complete Job history, including finished and failed Jobs, with state and period filters.
- Receive native notifications when Jobs and Inference Endpoints change state.
- Inspect live CPU, memory, network, and GPU metrics alongside live or archived Job logs.
- Switch to compact dashboard rows that keep only state, name, and actions visible.
- View Inference Endpoints and their current state.
- Track billing usage across Jobs, Endpoints, and Inference Providers.
- Refresh automatically while keeping your Hugging Face token in Keychain.
- Check for app updates on a schedule and install them with a restart.

## Keyboard shortcuts

- `⌘1` Jobs, `⌘2` Endpoints
- `⌘R` refresh, `⌘N` create/deploy, `⌘O` open on Hugging Face
- `⌘,` settings, `⌘Q` quit

## Installation

Download the latest DMG from [GitHub Releases](https://github.com/ehcalabres/Hugging-Face-MacOS/releases), open it, and drag **Hugging Face** to the Applications folder. The app requires macOS 14.0 or later.

Release builds are ad-hoc signed and are not notarized because the project does not currently use an Apple Developer membership. On first launch, Control-click the app and choose **Open**. If macOS still blocks it, go to **System Settings → Privacy & Security** and choose **Open Anyway**.

## App updates

The app checks GitHub Releases once a day while running, including after waking if a check is due. In Settings, choose every 6 or 12 hours, every day, every 2 days, every week, or manual checks. **Check Now** checks immediately. Checks do not require a Hugging Face token.

When a newer stable version is available, a Software Update window shows its release notes. Choose **Later** to defer until another scheduled check, or **Install and Restart** to download, verify, replace, and reopen the app. Install the app in a writable Applications folder first; updates cannot run from a DMG or a translocated app. If installation fails, see `~/Library/Logs/Hugging Face/Update.log` or install the DMG manually.

Older versions without the updater need one manual upgrade to gain this feature. Direct-download builds use a bundled installation script and run without App Sandbox; existing sandbox preferences are imported on first launch when readable. Tokens remain in Keychain, though macOS may ask you to grant access again after an ad-hoc signed update.

## Build from source

1. Open `Hugging Face MacOS.xcodeproj` in Xcode.
2. Build and run the **Hugging Face** scheme on macOS 14.0 or later.
3. Open Settings and add a Hugging Face token with access to the namespace you want to monitor.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and release instructions.
