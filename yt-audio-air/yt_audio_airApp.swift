//  YT Audio Air
//  Copyright (C) 2026 Anish Aryal
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

import SwiftUI
import AppKit
import WebKit

@main
struct yt_audio_airApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - PlayerPanel

class PlayerPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    static private(set) var shared: AppDelegate?
    
    var statusItem: NSStatusItem?
    var playerWindow: PlayerPanel!
    private var isPlayerPresented = false
    
    // Persistent WebView — created once, lives forever
    var webView: WKWebView!
    
    // App Nap prevention token
    private var appNapActivity: NSObjectProtocol?
    private var playbackWatchdog: DispatchSourceTimer?
    private var playbackEvaluationID: UUID?
    private var playbackEvaluationStarted = Date.distantPast
    private let systemVolume = SystemVolume()
    private var currentTrack: (title: String, artist: String, isPlaying: Bool)?
    
    // Click-outside monitors
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        UserDefaults.standard.register(defaults: [
            "hideImages": false,
            "grayscale": false,
            "hideHomeFeed": true,
            "hideShorts": true,
            "hideSubscriptions": true,
            "premiumUser": false,
            "loopPlayback": false,
            "autoplayNext": true,
            "randomizePlayback": false
        ])
        
        // Ensure the app runs as an accessory (hides from Dock)
        NSApp.setActivationPolicy(.accessory)
        
        setupWebView()
        setupPlayerWindow()
        setupStatusItem()
        disableAppNap()
        startPlaybackWatchdog()
        
        // Start BLE Peripheral Media Server
        BLEMediaServer.shared.start()
        BLEMediaServer.shared.broadcastPlaybackPreferences(
            loopPlayback: UserDefaults.standard.bool(forKey: "loopPlayback"),
            autoplayNext: UserDefaults.standard.bool(forKey: "autoplayNext"),
            randomizePlayback: UserDefaults.standard.bool(forKey: "randomizePlayback")
        )
    }
    
    // MARK: - WKWebView Setup
    
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        // Developer extras & Tab Discarding bypass
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        // Default data store for cookie persistence (Google auth, history, playlists)
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        
        // Register script message handler for BLE metadata sync
        configuration.userContentController.add(self, name: "bleMetadata")
        
        // ── Visibility API Override (document start) ──
        // Forces YouTube to believe the tab is always visible even when
        // the popover is closed and the WebView is parked offscreen.
        let visibilityJS = """
        (function() {
            Object.defineProperty(document, 'visibilityState', {
                get: function() { return 'visible'; },
                configurable: true
            });
            Object.defineProperty(document, 'hidden', {
                get: function() { return false; },
                configurable: true
            });
            window.addEventListener('visibilitychange', function(e) {
                e.stopImmediatePropagation();
            }, true);
            document.dispatchEvent(new Event('visibilitychange'));

            // Early path detection for SPA routing
            var pathname = window.location.pathname;
            var isHome = pathname === '/' || pathname === '';
            var isSub = pathname.startsWith('/feed/subscriptions');
            var isWatch = pathname.startsWith('/watch');
            document.documentElement.setAttribute('data-ytv-home', isHome ? 'true' : 'false');
            document.documentElement.setAttribute('data-ytv-sub', isSub ? 'true' : 'false');
            document.documentElement.setAttribute('data-ytv-watch', isWatch ? 'true' : 'false');
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: visibilityJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        
        // ── Aggressive CSS & JS RAM / Graphics Deflation (document end) ──
        guard let scriptURL = Bundle.main.url(forResource: "Playback", withExtension: "js"),
              let optimizationJS = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            fatalError("Missing bundled Playback.js")
        }
        configuration.userContentController.addUserScript(
            WKUserScript(source: optimizationJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 375, height: 550), configuration: configuration)
        webView.navigationDelegate = self
        
        // Mobile Safari user agent → forces m.youtube.com lightweight layout
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        
        if let url = URL(string: "https://m.youtube.com") {
            webView.load(URLRequest(url: url))
        }
    }
    
    // MARK: - Player Window Setup
    
    private func setupPlayerWindow() {
        playerWindow = PlayerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 375, height: 550),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        playerWindow.isReleasedWhenClosed = false
        playerWindow.title = "YT Audio Air"
        playerWindow.level = .statusBar
        playerWindow.hasShadow = true
        playerWindow.backgroundColor = .clear
        playerWindow.isOpaque = false
        playerWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        
        let hostingView = NSHostingView(rootView: ContentView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 375, height: 550)
        hostingView.autoresizingMask = [.width, .height]
        
        playerWindow.contentView = hostingView
        playerWindow.alphaValue = 0.01
        playerWindow.ignoresMouseEvents = true
        playerWindow.hasShadow = false
        parkWindowForBackgroundPlayback()
    }
    
    private func menuIconImage(from original: NSImage) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4.0, yRadius: 4.0)
        path.addClip()
        original.draw(in: rect)
        newImage.unlockFocus()
        return newImage
    }

    private func activeImage(from original: NSImage) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4.0, yRadius: 4.0)
        path.addClip()
        original.draw(in: rect)
        
        NSGraphicsContext.current?.saveGraphicsState()
        let dotRadius: CGFloat = 2.0
        let dotRect = NSRect(
            x: size.width - dotRadius * 2,
            y: 0.0,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        let dotPath = NSBezierPath(ovalIn: dotRect)
        NSColor.systemBlue.setFill()
        dotPath.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
        
        newImage.unlockFocus()
        return newImage
    }

    // MARK: - Status Item (Menu Bar Icon)
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            if let appIcon = NSImage(named: "AppIconImage") {
                button.image = menuIconImage(from: appIcon)
            } else {
                button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "YT Audio Air")
            }
            button.action = #selector(handleStatusItem)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    // MARK: - Status Item Click Handler
    
    @objc private func handleStatusItem() {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }
    
    var isWindowVisible: Bool {
        return isPlayerPresented
    }
    
    @objc func togglePopover() {
        guard let button = statusItem?.button else { return }
        
        if isWindowVisible {
            hideWindow()
        } else {
            showWindow(relativeTo: button)
        }
    }
    
    func showWindow(relativeTo button: NSButton) {
        guard let buttonWindow = button.window else { return }
        
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameInScreen = buttonWindow.convertToScreen(buttonFrameInWindow)
        
        let windowWidth: CGFloat = 375
        let windowHeight: CGFloat = 550
        
        let x = buttonFrameInScreen.origin.x + (buttonFrameInScreen.width / 2) - (windowWidth / 2)
        let y = buttonFrameInScreen.origin.y - windowHeight - 4
        
        if let appIcon = NSImage(named: "AppIconImage") {
            button.image = activeImage(from: appIcon)
        }

        isPlayerPresented = true
        playerWindow.alphaValue = 1
        playerWindow.ignoresMouseEvents = false
        playerWindow.hasShadow = true
        playerWindow.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
        playerWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // The WebView stays transparently parked during background playback. Redraw its
        // existing layers on reveal without reloading or disturbing playback.
        playerWindow.contentView?.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()
        webView.needsDisplay = true
        webView.layer?.setNeedsDisplay()
        playerWindow.displayIfNeeded()
        
        startMonitoringEvents()
    }
    
    func hideWindow() {
        isPlayerPresented = false
        playerWindow.alphaValue = 0.01
        playerWindow.ignoresMouseEvents = true
        playerWindow.hasShadow = false
        parkWindowForBackgroundPlayback()
        if let appIcon = NSImage(named: "AppIconImage") {
            statusItem?.button?.image = menuIconImage(from: appIcon)
        }
        stopMonitoringEvents()
    }

    // Keep a transparent sliver of the host window on a display. A fully
    // offscreen window is treated as occluded by WebKit and can suspend the
    // page's end-of-track and autoplay work even while audio is audible.
    private func parkWindowForBackgroundPlayback() {
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        playerWindow.setFrame(
            NSRect(
                x: screenFrame.minX - 374,
                y: screenFrame.minY,
                width: 375,
                height: 550
            ),
            display: false
        )
        playerWindow.orderFrontRegardless()
    }
    
    // MARK: - Click Outside Monitoring
    
    private func startMonitoringEvents() {
        stopMonitoringEvents()
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            let mouseLocation = NSEvent.mouseLocation
            if !self.playerWindow.frame.contains(mouseLocation) {
                if let button = self.statusItem?.button, button.window?.frame.contains(mouseLocation) == true {
                    // Let status bar action handle it
                    return event
                }
                self.hideWindow()
            }
            return event
        }
        
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return }
            let mouseLocation = NSEvent.mouseLocation
            if self.playerWindow.frame.contains(mouseLocation) {
                return
            }
            if let button = self.statusItem?.button, button.window?.frame.contains(mouseLocation) == true {
                return
            }
            self.hideWindow()
        }
    }
    
    private func stopMonitoringEvents() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }
    
    // MARK: - Right-Click Context Menu
    
    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        
        let menu = NSMenu()
        
        // Toggle Player
        let toggleItem = NSMenuItem(
            title: isWindowVisible ? "Hide Player" : "Show Player",
            action: #selector(menuTogglePlayer),
            keyEquivalent: "t"
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        // Options Panel
        let optionsItem = NSMenuItem(
            title: "Options…",
            action: #selector(menuShowOptions),
            keyEquivalent: ","
        )
        optionsItem.target = self
        menu.addItem(optionsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Go Home
        let homeItem = NSMenuItem(title: "Go to Home", action: #selector(menuGoHome), keyEquivalent: "h")
        homeItem.target = self
        menu.addItem(homeItem)
        
        // Copy Current Link
        if webView.url != nil {
            let copyLinkItem = NSMenuItem(title: "Copy Current Link", action: #selector(menuCopyLink), keyEquivalent: "l")
            copyLinkItem.target = self
            menu.addItem(copyLinkItem)
        }
        
        // Clear Cache Only
        let clearCacheItem = NSMenuItem(title: "Clear Cache Only", action: #selector(menuClearCacheOnly), keyEquivalent: "c")
        clearCacheItem.target = self
        menu.addItem(clearCacheItem)
        
        // Sign Out & Clear All Data
        let signOutItem = NSMenuItem(title: "Sign Out & Clear All Data", action: #selector(menuSignOut), keyEquivalent: "s")
        signOutItem.target = self
        menu.addItem(signOutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Support ☕
        let supportItem = NSMenuItem(title: "☕ Support Me", action: #selector(menuSupport), keyEquivalent: "")
        supportItem.target = self
        menu.addItem(supportItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit YT Audio Air", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        
        // Show then clear (one-shot menu)
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }
    
    // MARK: - Menu Actions
    
    @objc private func menuTogglePlayer() {
        togglePopover()
    }
    
    @objc private func menuShowOptions() {
        if !isWindowVisible {
            guard let button = statusItem?.button else { return }
            showWindow(relativeTo: button)
        }
        NotificationCenter.default.post(name: Notification.Name("ShowOptions"), object: nil)
    }
    
    @objc private func menuGoHome() {
        if let url = URL(string: "https://m.youtube.com") {
            webView.load(URLRequest(url: url))
        }
    }
    
    @objc private func menuCopyLink() {
        if let url = webView.url {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
    }
    
    @objc private func menuClearCacheOnly() {
        let alert = NSAlert()
        alert.icon = NSImage(named: "AppIconImage")
        alert.messageText = "Clear Cache Only"
        alert.informativeText = "This will remove cached files to free up disk and memory space. You will remain signed in. Continue?"
        alert.addButton(withTitle: "Clear Cache")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        
        if alert.runModal() == .alertFirstButtonReturn {
            let dataTypes: Set<String> = [
                WKWebsiteDataTypeDiskCache,
                WKWebsiteDataTypeMemoryCache
            ]
            WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: Date(timeIntervalSince1970: 0)) {
                self.webView.reload()
            }
        }
    }
    
    @objc private func menuSignOut() {
        let alert = NSAlert()
        alert.icon = NSImage(named: "AppIconImage")
        alert.messageText = "Sign Out & Clear All Data"
        alert.informativeText = "This will remove all saved cookies, cache, and sign you out of YouTube. Continue?"
        alert.addButton(withTitle: "Sign Out")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertFirstButtonReturn {
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: Date(timeIntervalSince1970: 0)) {
                self.webView.load(URLRequest(url: URL(string: "https://m.youtube.com")!))
            }
        }
    }
    
    @objc private func menuSupport() {
        if let url = URL(string: "https://anisharyal09.com.np/support?from=yt-audio-air") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - App Nap Prevention
    
    private func disableAppNap() {
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .suddenTerminationDisabled, .automaticTerminationDisabled],
            reason: "YT Audio Air — background audio playback"
        )
    }

    // This timer belongs to the application rather than the offscreen panel.
    // Evaluating a small script here also wakes end-of-track handling when
    // WebKit throttles page timers while the player UI is parked offscreen.
    private func startPlaybackWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: .milliseconds(500), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.updatePlaybackPreferences()
            self?.broadcastCurrentTrack()
        }
        playbackWatchdog = timer
        timer.resume()
    }

    func updatePlaybackPreferences() {
        guard let webView else { return }
        guard playbackEvaluationID == nil || Date().timeIntervalSince(playbackEvaluationStarted) > 2 else { return }
        let evaluationID = UUID()
        playbackEvaluationID = evaluationID
        playbackEvaluationStarted = Date()
        let displayPreferences = ["hideImages", "grayscale", "hideHomeFeed", "hideShorts", "hideSubscriptions", "premiumUser"]
            .map { "window.__\($0) = \(UserDefaults.standard.bool(forKey: $0));" }
            .joined(separator: "\n")
        let loop = UserDefaults.standard.bool(forKey: "loopPlayback")
        let autoplay = UserDefaults.standard.bool(forKey: "autoplayNext")
        let randomize = UserDefaults.standard.bool(forKey: "randomizePlayback")
        webView.evaluateJavaScript("""
        (function() {
            \(displayPreferences)
            window.__loopPlayback = \(loop);
            window.__autoplayNext = \(autoplay);
            window.__randomizePlayback = \(randomize);
            if (typeof window.__ytAudioAirMaintainPlayback === 'function') {
                return window.__ytAudioAirMaintainPlayback(\(loop), \(autoplay));
            }
            return 'not-ready';
        })();
        """) { [weak self] _, _ in
            guard self?.playbackEvaluationID == evaluationID else { return }
            self?.playbackEvaluationID = nil
        }
    }

    func playbackPreferencesDidChange() {
        updatePlaybackPreferences()
        BLEMediaServer.shared.broadcastPlaybackPreferences(
            loopPlayback: UserDefaults.standard.bool(forKey: "loopPlayback"),
            autoplayNext: UserDefaults.standard.bool(forKey: "autoplayNext"),
            randomizePlayback: UserDefaults.standard.bool(forKey: "randomizePlayback")
        )
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        
        let host = url.host?.lowercased() ?? ""
        
        // Keep YouTube and Google auth flows inside the WebView
        let internalHosts = ["youtube.com", "m.youtube.com", "www.youtube.com",
                             "accounts.google.com", "accounts.youtube.com",
                             "consent.youtube.com", "consent.google.com",
                             "myaccount.google.com", "gstatic.com",
                             "googleusercontent.com", "googlevideo.com",
                             "youtube-nocookie.com", "ytimg.com",
                             "play.google.com", "ggpht.com"]
        
        let isInternal = internalHosts.contains(where: { host.hasSuffix($0) })
        
        if isInternal {
            decisionHandler(.allow)
        } else if navigationAction.navigationType == .linkActivated {
            // Open external links in the default browser
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
    
    // MARK: - WKScriptMessageHandler
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "bleMetadata", let dict = message.body as? [String: Any] {
            let title = dict["title"] as? String ?? ""
            let artist = dict["artist"] as? String ?? ""
            let isPlaying = dict["isPlaying"] as? Bool ?? false
            let currentTime = (dict["currentTime"] as? NSNumber)?.doubleValue ?? 0
            let duration = (dict["duration"] as? NSNumber)?.doubleValue ?? 0
            NotificationCenter.default.post(
                name: Notification.Name("PlayerStateUpdated"),
                object: nil,
                userInfo: [
                    "isPlaying": isPlaying,
                    "isAd": dict["isAd"] as? Bool ?? false,
                    "isLoading": dict["isLoading"] as? Bool ?? false,
                    "playbackError": dict["playbackError"] as? String ?? "",
                    "currentTime": currentTime,
                    "duration": duration
                ]
            )
            currentTrack = (title, artist, isPlaying)
            broadcastCurrentTrack()
        }
    }

    private func broadcastCurrentTrack() {
        guard let track = currentTrack else { return }
        BLEMediaServer.shared.broadcastMetadata(
            title: track.title,
            artist: track.artist,
            isPlaying: track.isPlaying,
            volume: systemVolume.outputPercent(),
            loopPlayback: UserDefaults.standard.bool(forKey: "loopPlayback"),
            autoplayNext: UserDefaults.standard.bool(forKey: "autoplayNext"),
            randomizePlayback: UserDefaults.standard.bool(forKey: "randomizePlayback")
        )
    }

    // MARK: - Remote BLE Media Commands

    func seek(to seconds: Double) {
        guard seconds.isFinite, let wv = webView else { return }
        let time = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), max(0, seconds))
        wv.evaluateJavaScript("""
        (function() {
            var v = document.querySelector('video') || document.querySelector('.html5-main-video');
            if (v && !document.querySelector('.ad-showing, .ad-interrupting') && isFinite(v.duration)) v.currentTime = Math.min(\(time), v.duration);
        })();
        """, completionHandler: nil)
    }

    func setSystemVolume(_ volume: UInt8) {
        let target = min(Int(volume), 100)
        let script = "set volume output volume \(target)"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }

        if target > 0 {
            webView?.evaluateJavaScript("document.querySelectorAll('video').forEach(function(v) { v.muted = false; });", completionHandler: nil)
        }
    }
    
    func handleRemoteCommand(_ commandByte: UInt8) {
        guard let command = BLEMediaServer.Command(rawValue: commandByte), let wv = webView else { return }
        
        switch command {
        case .togglePlayPause:
            wv.evaluateJavaScript("window.__ytAudioAirSetPlaying?.();", completionHandler: nil)

        case .nextTrack:
            let js = """
            (function() {
                if (typeof window.__ytAudioAirNavigate === 'function') {
                    window.__ytAudioAirNavigate(1);
                } else {
                    if (!Array.isArray(window.__ytAudioAirBootstrapTransport)) window.__ytAudioAirBootstrapTransport = [];
                    if (window.__ytAudioAirBootstrapTransport.length < 16) window.__ytAudioAirBootstrapTransport.push(1);
                }
            })();
            """
            wv.evaluateJavaScript(js, completionHandler: nil)
            
        case .previousTrack:
            let js = """
            (function() {
                if (typeof window.__ytAudioAirNavigate === 'function') {
                    window.__ytAudioAirNavigate(-1);
                } else {
                    if (!Array.isArray(window.__ytAudioAirBootstrapTransport)) window.__ytAudioAirBootstrapTransport = [];
                    if (window.__ytAudioAirBootstrapTransport.length < 16) window.__ytAudioAirBootstrapTransport.push(-1);
                }
            })();
            """
            wv.evaluateJavaScript(js, completionHandler: nil)
            
        case .volumeUp:
            let script = "set volume output volume ((output volume of (get volume settings)) + 6.25)"
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
            let js = """
            (function() {
                var videos = document.querySelectorAll('video');
                videos.forEach(function(v) { v.muted = false; });
            })();
            """
            wv.evaluateJavaScript(js, completionHandler: nil)
            
        case .volumeDown:
            let script = "set volume output volume ((output volume of (get volume settings)) - 6.25)"
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }

        case .setVolume:
            break
        case .toggleLoop:
            let enabled = !UserDefaults.standard.bool(forKey: "loopPlayback")
            UserDefaults.standard.set(enabled, forKey: "loopPlayback")
            playbackPreferencesDidChange()
        case .toggleRandomize:
            let enabled = !UserDefaults.standard.bool(forKey: "randomizePlayback")
            UserDefaults.standard.set(enabled, forKey: "randomizePlayback")
            playbackPreferencesDidChange()
        case .toggleAutoplayNext:
            let enabled = !UserDefaults.standard.bool(forKey: "autoplayNext")
            UserDefaults.standard.set(enabled, forKey: "autoplayNext")
            playbackPreferencesDidChange()
        }
    }
}
