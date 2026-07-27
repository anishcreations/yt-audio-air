# YT Audio Air Remote (Android & Wear OS Companion App)

A native Android & Wear OS companion app for **YT Audio Air** on macOS.

Streams live track metadata (title, channel, play/pause state) and remote transport controls (Play/Pause, Next, Prev, Volume) directly to your Android Lock Screen, Notification Shade, and Wear OS Galaxy Watch over Bluetooth Low Energy (BLE) — completely offline without local Wi-Fi or IP configuration. (See [UPDATES.md](UPDATES.md) for companion app release notes).

---

## Features

- **Offline BLE Connectivity**: Auto-discovers and connects to `yt-audio-air` on your Mac via GATT Service `12345678-1234-1234-1234-123456789abc`.
- **System Media Player Integration**: Drives native Android Lock Screen cards and Notification Shade seekbar volume control (`MediaSessionCompat`).
- **Wear OS / Galaxy Watches**: Intermediary wrist media controls and bezel volume dial (relayed via paired Android phone over BLE to Mac).
- **Minimal UI**: Glassmorphic dark UI with live connection badge, track card, and soothing minimal footer.

---

## How to Build & Run in Android Studio

1. Open **Android Studio**.
2. Select **Open** and select the `android/` directory:
   `yt-audio-air/android`
3. Click **Sync Project with Gradle Files**.
4. Connect your Android phone via USB (with **USB Debugging** enabled in phone Developer Options).
5. Click **Run (▶)** (`Shift + F10`) to build the `.apk` and launch on your phone.

---

## License

- Licensed under the Apache License 2.0.
