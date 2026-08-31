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

## Keyboard shortcuts

- `⌘1` Jobs, `⌘2` Endpoints
- `⌘R` refresh, `⌘N` create/deploy, `⌘O` open on Hugging Face
- `⌘,` settings, `⌘Q` quit

## Getting started

1. Open `Hugging Face MacOS.xcodeproj` in Xcode.
2. Build and run the **Hugging Face** scheme on macOS 26.5 or later.
3. Open Settings and add a Hugging Face token with access to the namespace you want to monitor.
