# YT Audio Air Remote (Android & Wear OS Companion App)

A native Android & Wear OS companion app for **YT Audio Air** on macOS.

Streams live track metadata (title, channel, play/pause state) and remote transport controls (Play/Pause, Next, Prev, Volume) directly to your Android Lock Screen, Notification Shade, and Wear OS Galaxy Watch over Bluetooth Low Energy (BLE) — completely offline without local Wi-Fi or IP configuration.

---

## Features

- **Offline BLE Connectivity**: Auto-discovers and connects to `yt-audio-air` on your Mac via GATT Service `12345678-1234-1234-1234-123456789abc`.
- **System Media Player Integration**: Drives native Android Lock Screen cards and Notification Shade seekbar volume control (`MediaSessionCompat`).
- **Wear OS / Galaxy Watch 4 Classic**: Full wrist playback controls and hardware bezel volume dial integration.
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

## Support & License

- Website: [https://anisharyal09.com.np/support?from=yt-audio-air-phone](https://anisharyal09.com.np/support?from=yt-audio-air-phone)
- Licensed under the Apache License 2.0.
