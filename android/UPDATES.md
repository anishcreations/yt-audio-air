# Android & Wear OS Companion App Changelog

All notable changes to the **YT Audio Air Companion App** (`android/`) are documented in this file.

---

## [v1.1.1] - 2026-08-05

### Fixed
- **Exact Slider Volume Sync**: Phone slider positions now use a debounced absolute BLE command, so large jumps such as 100% to 0% reach the exact Mac output volume instead of being capped at four incremental steps. Phone buttons and Wear OS adjustments remain incremental and update the local `VolumeProvider` immediately.

---

## [v1.1.0] - 2026-07-28

### Added & Fixed
- **512-Byte ATT MTU Expansion**: Requests 512-byte ATT MTU upon connecting to Mac over BLE, expanding notification payload capacity from 20 bytes to 512 bytes. Prevents JSON packet truncation and ensures un-truncated song titles, channel names, and playing status updates.
- **Dual-Stage JSON & Regex Fallback Parser**: Added robust regex fallback parsing (`Regex("\"title\":\"([^\"]+)\"")` & `Regex("\"isPlaying\":(true|false)")`) to extract track metadata cleanly even under low-MTU conditions.
- **Main UI Looper Dispatching**: Wrapped `MediaSessionCompat.setPlaybackState()`, `updateNotification()`, and status broadcasts inside `Handler(Looper.getMainLooper()).post`. Now incoming BLE notifications refresh the Phone App UI, Lock Screen Card, Notification Shade, and Galaxy Watch 4 Classic with zero latency.
- **Synced Output Volume Controls**: Synchronized phone volume buttons, notification seekbar slider, and Galaxy Watch 4 Classic rotating bezel dial with Mac master output volume (+6.25% / -6.25% per step).
- **Android 14 Internal Broadcast Security Scope**: Added explicit `RECEIVER_NOT_EXPORTED` registration for intra-app status broadcasts between `BLEMediaService` and `MainActivity`.
- **Dynamic Track & Channel Display**: Falls back gracefully to song title when channel/artist string is missing or generic `"YouTube"`.


---

## [v1.0.0] - 2026-07-27

### Added
- **Initial Release**: Standalone Kotlin Android project for YT Audio Air companion.
- **Offline BLE GATT Client**: Scans for and auto-connects to `yt-audio-air` GATT service (`12345678-1234-1234-1234-123456789abc`) over Bluetooth Low Energy.
- **MediaSession System Player**: Native Lock Screen Media Card and Notification Shade volume slider integration.
- **Wear OS / Galaxy Watches**: Intermediary wrist media controls and bezel volume dial (relayed via paired Android phone over BLE to Mac).
- **Dark Glassmorphic UI**: Interactive connection status badge, live track metadata card, and transport buttons.
