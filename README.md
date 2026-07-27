<div align="center">
  <br>
  <img src="yt-audio-air/Assets.xcassets/AppIcon.appiconset/appicon_128x128.png" width="120" height="120" alt="YT Audio Air Logo">
  <br>
  <h1>
    YT Audio Air
  </h1>
  <br>

  <img src="https://img.shields.io/badge/Platform-macOS%2014.0+-blue?logo=apple" alt="Platform: macOS 14.0+" />
  <a href="updates.md"><img src="https://img.shields.io/badge/App-v1.4.0-green" alt="App Version: v1.4.0" /></a>
  <img src="https://img.shields.io/badge/Built%20with-Swift%205%20%2B%20WKWebView-orange?logo=swift" alt="Built with Swift 5 + WKWebView" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-blue" alt="License: Apache 2.0" /></a>
  <a href="SECURITY.md"><img src="https://img.shields.io/badge/Security-Policy-brightgreen" alt="Security Policy" /></a>
</div>

A native macOS menu bar app for resource-efficient YouTube audio streaming.

No Electron, no Chromium — built with Swift and Apple's system **WKWebView**. Sits in your menu bar, plays YouTube audio in the background, and uses a fraction of the RAM a browser tab would. (See [updates.md](updates.md) for the latest release notes).

---

## Why Build This?

### The Problem
Web browsers (especially Firefox and Chrome) are notoriously resource-heavy, consuming a massive amount of memory and GPU rendering power just to stream background audio. And also other open-source, third-party clients often feel bloated or heavy, or simply don't meet my need.

At the same time, most minimal or custom players strip away account features entirely. Syncing playback history directly to a main YouTube account is a must-have criteria (simply for seamless history tracking), for no reason, i just want to keep it as it is.

### The Solution
Finding nothing that was minimal, lightweight, bug-free, and supported direct history syncing, **YT Audio Air** was built. It runs natively in the macOS menu bar, keeps history synced, and operates on a fraction of a browser's resources.

And **NO data is collected**, not even interested in doing so :)

This project was built using Xcode and Swift, with developer assistance from:
- **Open Code**
- **Antigravity**


---

## Features

- **Background Playback** — Uses a persistent `NSPanel` with the WebView permanently embedded. Closing the UI parks the window offscreen; audio never stops.
- **Instant Ad Skipping** — Detects ads via `.ad-showing` class → mutes → 16x speed → seeks to end → clicks skip. Ads vanish silently in milliseconds.
- **Minimal Resource Usage** — Video element deflated to 1×1px. Quality forced to 144p. GPU raster bypassed. No MutationObservers — single 250ms polling loop handles everything.
- **Native Two-Way BLE Remote Control & Metadata Sync** — Communicates natively over Bluetooth Low Energy (BLE) with an Android companion app (and Wear OS smartwatches like Galaxy Watch 4 Classic). Supports media transport control (Play/Pause, Next, Prev, Volume Up/Down) and streams live track metadata (`title`, `artist/channel`, `isPlaying` state) over BLE without requiring local Wi-Fi, IP configurations, or third-party bridge software.
- **Locked-Down Watch Page** — The video player frame is slightly dimmed for visual comfort (0.8 opacity). Comments, action bars, and related items are completely hidden, while the remaining title and channel section below the player is permanently locked down, unclickable, and ghosted (0.6 opacity) to maintain a pristine, distraction-free pure audio experience. You can still copy the video link from the status bar right-click menu.
- **Auto-Unmute** — Defeats YouTube mobile's autoplay muting by continuously forcing `video.muted = false` on watch pages.
- **Hide Images & Avatars** — Toggle to visually hide all video thumbnails and channel profile pictures. Uses non-collapsing styling to preserve card grid alignment and keep video duration overlays fully visible.
- **Grayscale Mode** — Native-performance grayscale filter option for the entire interface, hardware layer composited (`will-change: transform`) to prevent WebKit animation or sticky-scroll glitches.
- **Settings Control Popover** — A glassmorphic options card to toggle preferences (Hide Images, Grayscale, Go to Home) with clean right-aligned switches.
- **Navigation Bar** — Back, Forward, Refresh, settings controls, and a high-resolution brand logo.
- **Right-Click Menu & Settings Shortcut** — Toggle player window, go home, open settings directly (`Options...` item or `⌘,` hotkey), clear cache (stay signed in), sign out & clear all data, support link, and quit.
- **Privacy** — 100% client-side. No trackers, no telemetry, no third-party servers. Cookies stored in macOS's sandboxed WebKit container.

---

## How It Works

### Visibility Spoofing
Overrides the Visibility API at document start so YouTube thinks the player tab is always active — even when the window is parked at `(-20000, -20000)`:
```javascript
Object.defineProperty(document, 'visibilityState', { get: () => 'visible' });
Object.defineProperty(document, 'hidden', { get: () => false });
```

### Layout Deflation
Aggressive CSS injection strips everything except the player and playlist queue:
```css
ytm-comment-section-renderer, ytm-slim-video-action-bar-renderer,
ytm-engagement-panel-section-list-renderer, ytm-video-description-header-renderer,
ytm-item-section-renderer[section-identifier="related-items"],
ytm-reel-shelf-renderer { display: none !important; }
```

### Ad Detection
Uses YouTube's own `.ad-showing` class on the player element — no overlay heuristics that can false-positive. When detected: mute → 16x speed → seek to end → click skip button.

### Image Hiding & Grayscale
- **Image Hiding**: Injects dynamic CSS to set `opacity: 0` on `img` and `lazy-image` elements rather than `display: none`. This preserves the dimensions of card containers, allowing video duration text overlays to display perfectly on top of dark placeholder backgrounds.
- **Grayscale Mode**: Injects a root-level `filter: grayscale(100%)` rule on the `html` tag. To keep the slide-in header functional during scroll under a root-level filter, it applies layer acceleration (`will-change: transform`) to YouTube's mobile header elements, forcing WebKit to create a separate compositing layer.

### Unified 250ms Loop
A single `setInterval(globalUpdate, 250)` replaces heavy DOM observers. Each tick handles ad skipping, 144p quality enforcement, autoplay initiation, force-unmuting, and dynamic preference evaluation.

---

## Download & Installation

### Option 1: Via Homebrew Tap (Recommended 🚀)

Installing via the custom Homebrew Tap is the recommended method because it **automatically bypasses macOS Gatekeeper**. The tap's postflight installation script strips the quarantine attributes (`xattr -cr`), meaning you do **not** need to manually override security permissions ("Open Anyway") or right-click to run the app.

To install, simply run:

```bash
brew install anisharyal09/tap/yaa
```

*Or, if you prefer using the full name:*

```bash
brew install anisharyal09/tap/yt-audio-air
```
---

### Option 2: Pre-built Release (Manual)

If you prefer not to use Homebrew:

1. Go to the [Releases](https://github.com/anisharyal09/yt-audio-air/releases) page on GitHub.
2. Download the latest `yt-audio-air.zip` from the release assets.
3. Double-click to extract the ZIP archive, yielding the `yt-audio-air.app` bundle.
4. Drag and drop the app into your `/Applications` directory.

#### First Launch (Bypassing macOS Gatekeeper Manually)
Because the pre-built ZIP release is compiled and released without an Apple Developer signature, macOS will block it on the first launch.
To allow the app to run:
1. Double-click `yt-audio-air.app` to attempt to run it. macOS will show a warning dialog and block it. Click **Cancel** (or **OK**).
2. Open **System Settings** on your Mac and navigate to **Privacy & Security**.
3. Scroll down to the **Security** section. You will see a message stating ***"yt-audio-air.app" was blocked from use because it is not from an identified developer***.
4. Click **Open Anyway** (you may need to enter your Mac's password or use Touch ID).
5. Attempt to open `yt-audio-air.app` once more, and click **Open** on the confirmation dialog.
6. Once completed, the app will launch and it will appear in menu bar.

---

## Building from Source

If you prefer to compile the application locally yourself:

1. Open `yt-audio-air.xcodeproj` in Xcode.
2. Select the `yt-audio-air` target and select scheme **My Mac**.
3. Build the project using `⌘B`.
4. To package a standalone release binary, navigate to **Product > Archive**, then click **Distribute App** → **Copy App** to save the compiled `.app` bundle.

---

## Android & Wear OS Companion App (`android/`)

`yt-audio-air` includes a native Kotlin Android companion project (`android/`) that pairs over Bluetooth Low Energy (BLE) without local Wi-Fi or IP configuration.

### Features
- **Phone Lock Screen & Notification Card**: Displays real-time song title, channel name, album artwork, and transport controls (Play/Pause, Next, Prev, Volume Seekbar).
- **Wear OS / Galaxy Watch 4 Classic**: Native wrist media controls and bezel volume dial integration.
- **Interactive Dark UI**: Dark glassmorphic interface with connection status badge, live track card, optimistic button response, versioning footer (`v1.0.0`), and Support Me link.

### Building in Android Studio
1. Open **Android Studio**.
2. Select **Open** and navigate to the `android/` directory:
   `yt-audio-air/android`
3. Click **Sync Project with Gradle Files**.
4. Connect your Android phone via USB (with USB Debugging enabled) and click **Run (▶)** (`Shift + F10`).

---

## 💡 Troubleshooting & Support

If you encounter any loading issues, playback lags, or general oddities:
- Simply **refresh/reload the page** by clicking the reload button (`arrow.clockwise`) in the player header to reset the WebKit instance state.
- If issues persist, please reach out via [Email Inquiry](mailto:anish.creations.hq@gmail.com?subject=YT%20Audio%20Air%20-%20Support%20%26%20Feedback) or contact directly online at [anisharyal09.com.np](https://anisharyal09.com.np/#contact).

---

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.