# Notchify

<p align="center">
  <img src="./readme/ic_launcher.png" alt="Notchify" width="160" />
</p>

<p align="center">
  <strong>A sleek, compact MacBook notch drawer for storage, quick actions, music, and live camera mirror.</strong>
</p>

<p align="center">
  <strong>Notchify by Christian Saguirre</strong><br />
  <em>Inspired to make by Nadiane</em>
</p>

<p align="center">
  <a href="https://github.com/chrischancode/nook-app/releases/latest">Download Latest Release</a> ·
  <a href="https://github.com/chrischancode/nook-app/actions">Builds & Artifacts</a>
</p>

---

## ⚡ Features

- 📁 **File Shelf & Storage**: Drag and drop files to hold them temporarily in your notch drawer with live, high-resolution thumbnail previews. Drag them out anytime to Finder, Discord, Slack, or Mail.
- 📡 **Instant AirDrop**: Drop files into the AirDrop zone or tab to send them immediately via macOS native AirDrop.
- 🪞 **Live Camera Mirror**: Integrated real-time mirror flipped horizontally (`scaleEffect(x: -1, y: 1)`) with an in-drawer power switch.
- 🎵 **Mini Music Player**: Persistent audio control widget for Apple Music, Spotify, and more. Displays current song, album art, and 1-tap play/pause.
- 📸 **Quick Actions**: One-click **Capture** (opens macOS Screenshot utility) and **Lock** (puts display to sleep).
- 🖱️ **Auto-Glide Notch**: Dragging files towards the top of your screen automatically opens the notch drawer smoothly.

---

## 📥 Quick Download & Installation

### Step 1: Download
- Download the latest `Notchify.zip` from **[Releases](https://github.com/chrischancode/nook-app/releases/latest)** or grab the latest build artifact from **[GitHub Actions](https://github.com/chrischancode/nook-app/actions)**.

### Step 2: Install
1. Unzip the downloaded file to find `Notchify.app`.
2. Drag `Notchify.app` into your **Applications** folder (`/Applications`).

---

## 💻 Terminal Command (Important)

Because Notchify is downloaded directly from GitHub rather than the Mac App Store, macOS Gatekeeper may show a warning:  
> *"Notchify is damaged and can't be opened"* or *"macOS cannot verify the developer"*.

To resolve this instantly, open your Mac **Terminal** (press `Cmd + Space`, type `Terminal`, and hit `Enter`) and run this command:

```bash
xattr -cr /Applications/Notchify.app
```

> **Why this is needed**: This command clears the macOS quarantine attribute (`com.apple.quarantine`) from the application so macOS allows Notchify to open immediately.

---

## ⚙️ Permissions Setup

When running Notchify for the first time, grant the necessary permissions:
1. **Camera**: Required for the live Camera Mirror preview (`System Settings > Privacy & Security > Camera`).
2. **Accessibility**: Allows Notchify to position itself accurately at your notch and handle global shortcuts (`System Settings > Privacy & Security > Accessibility`).

---

## 🛠️ Build From Source

To compile Notchify manually using Xcode:

```bash
git clone https://github.com/chrischancode/nook-app.git
cd nook-app
xcodebuild -scheme Nook -configuration Release build
```

---

## 👤 Credits

- **Notchify by**: Christian Saguirre
- **Inspired to make by**: Nadiane
- Inspired by modern macOS Dynamic Island experiences.
