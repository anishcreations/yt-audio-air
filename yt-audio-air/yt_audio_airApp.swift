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
    
    // Persistent WebView — created once, lives forever
    var webView: WKWebView!
    
    // App Nap prevention token
    private var appNapActivity: NSObjectProtocol?
    
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
            "loopPlayback": false
        ])
        
        // Ensure the app runs as an accessory (hides from Dock)
        NSApp.setActivationPolicy(.accessory)
        
        setupWebView()
        setupPlayerWindow()
        setupStatusItem()
        disableAppNap()
        
        // Start BLE Peripheral Media Server
        BLEMediaServer.shared.start()
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
        let optimizationJS = """
        (function() {
            if (!window.location.hostname.includes('youtube.com')) return;
            if (window.__ytAudioAirOpt) return;
            window.__ytAudioAirOpt = true;

            if (typeof window.__needsAutoplay === 'undefined') {
                window.__needsAutoplay = false;
            }

            var transport = window.__ytAudioAirTransport || {
                busy: false,
                queue: [],
                retries: 0,
                timer: null,
                activeDirection: 0,
                waiting: false,
                startedAt: 0,
                startingVideoId: null
            };
            if (!Array.isArray(transport.queue)) transport.queue = [];
            transport.activeDirection = transport.activeDirection || 0;
            transport.waiting = transport.waiting === true;
            window.__ytAudioAirTransport = transport;

            function transportButton(direction) {
                var mobileButtons = document.querySelectorAll('#player-control-overlay .player-middle-controls-prev-next-button');
                var button = mobileButtons.length > 0
                    ? mobileButtons[direction > 0 ? mobileButtons.length - 1 : 0]
                    : document.querySelector(direction > 0
                        ? '.player-control-next, .ytp-next-button, button[aria-label="Next video"], button[aria-label="Next"]'
                        : '.player-control-prev, .ytp-prev-button, button[aria-label="Previous video"], button[aria-label="Previous"]');
                return button && button.isConnected && !button.disabled && button.getAttribute('aria-disabled') !== 'true'
                    ? button
                    : null;
            }

            function currentVideoId() {
                var player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                if (player && typeof player.getVideoData === 'function') {
                    try {
                        var data = player.getVideoData();
                        if (data && data.video_id) return data.video_id;
                    } catch (_) {}
                }
                try { return new URL(window.location.href).searchParams.get('v'); } catch (_) { return null; }
            }

            function drainPendingTransport() {
                if (transport.busy || transport.queue.length === 0) return;
                var direction = transport.queue.shift();
                transport.busy = true;
                transport.activeDirection = direction;
                transport.waiting = true;
                transport.timer = setTimeout(function() {
                    transport.timer = null;
                    transport.busy = false;
                    transport.activeDirection = 0;
                    transport.waiting = false;
                    window.__ytAudioAirNavigate(direction);
                }, 150);
            }

            function releaseTransport(retryActive) {
                var activeDirection = transport.activeDirection;
                clearTimeout(transport.timer);
                transport.timer = null;
                transport.busy = false;
                transport.retries = 0;
                transport.activeDirection = 0;
                transport.waiting = false;
                transport.startedAt = 0;
                transport.startingVideoId = null;
                if (retryActive && activeDirection && transport.queue.length < 16) {
                    transport.queue.unshift(activeDirection);
                }
                drainPendingTransport();
            }

            window.__ytAudioAirNavigate = function(direction) {
                direction = direction < 0 ? -1 : 1;
                if (transport.busy) {
                    if (transport.queue.length < 16) transport.queue.push(direction);
                    return 'queued';
                }

                var player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                var ready = !!player;
                if (ready && typeof player.isReady === 'function') {
                    try { ready = player.isReady(); } catch (_) { ready = false; }
                }
                var button = transportButton(direction);

                if (!ready && !button) {
                    if (transport.retries < 6) {
                        transport.retries += 1;
                        transport.busy = true;
                        transport.activeDirection = direction;
                        transport.waiting = true;
                        clearTimeout(transport.timer);
                        transport.timer = setTimeout(function() {
                            transport.busy = false;
                            transport.activeDirection = 0;
                            transport.waiting = false;
                            window.__ytAudioAirNavigate(direction);
                        }, 150);
                    } else {
                        releaseTransport(false);
                    }
                    return 'waiting';
                }

                transport.retries = 0;
                transport.busy = true;
                transport.activeDirection = direction;
                transport.waiting = false;
                transport.startedAt = Date.now();
                transport.startingVideoId = currentVideoId();
                window.__needsAutoplay = true;

                var method = direction > 0 ? 'nextVideo' : 'previousVideo';
                var usedPlayerAPI = false;
                var acted = false;

                if (ready && typeof player[method] === 'function') {
                    try {
                        player[method]();
                        usedPlayerAPI = true;
                        acted = true;
                    } catch (_) {}
                }
                if (!acted && button) {
                    button.click();
                    acted = true;
                }
                if (!acted) {
                    releaseTransport(false);
                    return 'unavailable';
                }

                clearTimeout(transport.timer);
                function watchdog() {
                    if (!transport.busy) return;
                    if (currentVideoId() !== transport.startingVideoId) {
                        releaseTransport(false);
                        return;
                    }

                    var activePlayer = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                    var state = null;
                    if (activePlayer && typeof activePlayer.getPlayerState === 'function') {
                        try { state = activePlayer.getPlayerState(); } catch (_) {}
                    }
                    var rebuilding = !activePlayer || state === -1 || state === 3 || state === 5;
                    if (rebuilding && Date.now() - transport.startedAt < 5000) {
                        transport.timer = setTimeout(watchdog, 500);
                    } else {
                        releaseTransport(false);
                    }
                }
                transport.timer = setTimeout(watchdog, 1500);

                return usedPlayerAPI ? 'player-api' : 'button';
            };

            if (Array.isArray(window.__ytAudioAirBootstrapTransport)) {
                window.__ytAudioAirBootstrapTransport.slice(0, 16).forEach(function(direction) {
                    transport.queue.push(direction);
                });
                delete window.__ytAudioAirBootstrapTransport;
                drainPendingTransport();
            }

            var css = `
                /* ═══ VIDEO VISUAL DEFLATION ═══
                   Keeps layout dimensions so YouTube player init passes,
                   but hides visual output to prevent GPU frame rendering. */
                video {
                    opacity: 0.001 !important;
                    pointer-events: none !important;
                    width: 1px !important;
                    height: 1px !important;
                    transform: scale(0.001) !important;
                }
                .player-container, #player-container-id, .html5-video-player,
                .video-stream {
                    background: #000000 !important;
                }

                /* Show playlist panel and style it as a clean text list */
                ytm-playlist-panel-renderer {
                    display: block !important;
                    background: #121212 !important;
                    border: 1px solid rgba(255,255,255,0.08) !important;
                    border-radius: 8px !important;
                    margin: 8px !important;
                    padding: 8px !important;
                }

                /* Hide thumbnails in playlist panel to save memory & CPU */
                ytm-playlist-panel-video-renderer .ytm-thumbnail-canvas,
                ytm-playlist-panel-video-renderer lazy-image,
                ytm-playlist-panel-video-renderer img {
                    display: none !important;
                }

                /* Make playlist list items compact */
                ytm-playlist-panel-video-renderer {
                    padding: 6px 4px !important;
                    border-bottom: 1px solid rgba(255,255,255,0.05) !important;
                }

                /* Playlist text layout adjustments */
                ytm-playlist-panel-video-renderer .playlist-panel-video-metadata {
                    padding: 2px 4px !important;
                    margin: 0 !important;
                }
                ytm-playlist-panel-video-renderer h4.playlist-panel-video-title {
                    font-size: 12px !important;
                    font-weight: 500 !important;
                    color: #ffffff !important;
                    line-height: 1.3 !important;
                }
                ytm-playlist-panel-video-renderer .playlist-panel-video-byline {
                    font-size: 10px !important;
                    color: #aaaaaa !important;
                }

                /* ═══ HEAVY VISUAL/RAM DEFLATION ═══ */
                /* Live chat & comments */
                ytm-live-chat-renderer, #chat, iframe[src*="live_chat"],
                ytm-comment-section-renderer, ytm-comments-entry-point-header-renderer,
                #comment-section, .comment-section-renderer,
                /* Like/dislike/share/save buttons */
                ytm-slim-video-action-bar-renderer,
                /* Related recommendations grid on watch page */
                ytm-item-section-renderer[section-identifier="related-items"],
                /* Ads & Promotions (excl .ad-showing to avoid freezing player) */
                .companion-ad, #masthead-ad, ytm-companion-ad-renderer,
                .ad-container, .promoted-item, ytm-promoted-item,
                .ytm-promoted-sparkles-web-renderer, ytm-upsell-dialog-renderer,
                #upsell-dialog, .video-ads, .ytp-ad-overlay-container,
                .ytp-ad-skip-button-slot, .ytp-ad-module,
                ytm-companion-slot, ytm-promoted-sparkles-text-search-renderer,
                .ytm-autonav-bar,
                /* Animated thumbnails/avatars */
                .ytm-animated-thumbnail,
                /* Banners & promotions */
                .yt-banner, ytm-banner-promo-renderer,
                /* Hide Shorts, Subscriptions, and You */
                ytm-pivot-bar-renderer-content[pivot-bar-item-id="pivot-shorts"],
                ytm-reel-shelf-renderer,
                /* Hide Tap to Unmute Overlay */
                .ytp-unmute, .ytp-unmute-box, .ytp-unmute-text, .ytm-unmute-box, .ytm-unmute-text, [class*="unmute-box"], [class*="unmute-button"] {
                    display: none !important;
                    height: 0 !important;
                    max-height: 0 !important;
                    overflow: hidden !important;
                    visibility: hidden !important;
                }

                /* Reduce YouTube top header bar size */
                ytm-header-bar, .ytm-header-bar {
                    height: 38px !important;
                    min-height: 38px !important;
                    padding: 0 4px !important;
                }
                ytm-header-bar .header-bar-logo-container,
                ytm-header-bar .logo-container,
                ytm-header-bar .logo,
                ytm-header-bar svg {
                    transform: scale(0.75) !important;
                    transform-origin: left center !important;
                }
                ytm-header-bar button,
                ytm-header-bar .header-bar-icon,
                ytm-header-bar a {
                    transform: scale(0.75) !important;
                    transform-origin: center center !important;
                }
                ytm-search-header-renderer, .ytm-search-header-renderer {
                    height: 38px !important;
                    min-height: 38px !important;
                    padding: 0 4px !important;
                }
                ytm-search-header-renderer form {
                    transform: scale(0.85) !important;
                    transform-origin: center center !important;
                }
                /* Dim the main video player frame slightly */
                #player-container-id, .html5-video-player, #player {
                    opacity: 0.8 !important;
                }

                /* Dim and completely lock down EVERYTHING below the video player */
                ytm-single-column-watch-next-results-renderer {
                    pointer-events: none !important;
                    opacity: 0.6 !important;
                    user-select: none !important;
                }

                /* Keep YouTube's player chrome inert; native SwiftUI controls
                   provide the intentionally minimal transport UI. */
                html[data-ytv-watch="true"] #player-container-id,
                html[data-ytv-watch="true"] #movie_player,
                html[data-ytv-watch="true"] .html5-video-player {
                    cursor: default !important;
                }
                html[data-ytv-watch="true"] #player-control-container,
                html[data-ytv-watch="true"] #player-control-overlay,
                html[data-ytv-watch="true"] .player-controls-content,
                html[data-ytv-watch="true"] .player-controls-background,
                html[data-ytv-watch="true"] .player-controls-top,
                html[data-ytv-watch="true"] .player-controls-middle,
                html[data-ytv-watch="true"] .player-controls-bottom,
                html[data-ytv-watch="true"] .ytp-chrome-bottom,
                html[data-ytv-watch="true"] .ytp-chrome-controls {
                    opacity: 0 !important;
                    visibility: hidden !important;
                    pointer-events: none !important;
                }
            `;

            var style = document.createElement('style');
            style.id = 'yt-audio-air-opt';
            style.textContent = css;
            document.documentElement.appendChild(style);

            var wasAdActive = false;

            function globalUpdate() {
                // Update early path detection attributes
                var pathname = window.location.pathname;
                var isHome = pathname === '/' || pathname === '';
                var isSub = pathname.startsWith('/feed/subscriptions');
                var isWatch = pathname.startsWith('/watch');
                document.documentElement.setAttribute('data-ytv-home', isHome ? 'true' : 'false');
                document.documentElement.setAttribute('data-ytv-sub', isSub ? 'true' : 'false');
                document.documentElement.setAttribute('data-ytv-watch', isWatch ? 'true' : 'false');

                // Check if images need to be hidden/restored
                var hideImages = window.__hideImages === true;
                var imgStyle = document.getElementById('yt-audio-air-hide-images');
                if (hideImages) {
                    if (!imgStyle) {
                        imgStyle = document.createElement('style');
                        imgStyle.id = 'yt-audio-air-hide-images';
                        imgStyle.textContent = 'img, lazy-image, .ytp-cued-thumbnail-overlay { opacity: 0 !important; } .ytm-thumbnail-canvas, .thumbnail, .media-item-thumbnail-container { background: #1c1c1e !important; border-radius: 8px !important; }';
                        document.documentElement.appendChild(imgStyle);
                    }
                } else {
                    if (imgStyle) {
                        imgStyle.remove();
                    }
                }

                // Check if grayscale needs to be applied/removed
                var grayscale = window.__grayscale === true;
                var grayStyle = document.getElementById('yt-audio-air-grayscale');
                if (grayscale) {
                    if (!grayStyle) {
                        grayStyle = document.createElement('style');
                        grayStyle.id = 'yt-audio-air-grayscale';
                        grayStyle.textContent = 'html { filter: grayscale(100%) !important; } ytm-header-bar, .ytm-header-bar, ytm-mobile-topbar-renderer { will-change: transform !important; }';
                        document.documentElement.appendChild(grayStyle);
                    }
                } else {
                    if (grayStyle) {
                        grayStyle.remove();
                    }
                }

                // Check if hideHomeFeed needs to be applied/removed
                var hideHome = window.__hideHomeFeed === true;
                var homeStyle = document.getElementById('yt-audio-air-hide-home');
                if (hideHome) {
                    if (!homeStyle) {
                        homeStyle = document.createElement('style');
                        homeStyle.id = 'yt-audio-air-hide-home';
                        homeStyle.textContent = 'html[data-ytv-home="true"] ytm-browse, html[data-ytv-home="true"] ytm-single-column-browse-results-renderer, html[data-ytv-home="true"] ytm-section-list-renderer, html[data-ytv-home="true"] #contents, html[data-ytv-home="true"] #primary, html[data-ytv-home="true"] .tab-content { display: none !important; height: 0 !important; }';
                        document.documentElement.appendChild(homeStyle);
                    }
                } else {
                    if (homeStyle) homeStyle.remove();
                }

                // Check if hideShorts needs to be applied/removed
                var hideSh = window.__hideShorts === true;
                var shortsStyle = document.getElementById('yt-audio-air-hide-shorts');
                if (hideSh) {
                    if (!shortsStyle) {
                        shortsStyle = document.createElement('style');
                        shortsStyle.id = 'yt-audio-air-hide-shorts';
                        shortsStyle.textContent = 'a[href*="/shorts"], ytm-reel-shelf-renderer, ytm-shorts-lockup-view-model, ytm-shorts-video-renderer, ytm-pivot-bar-item-renderer:has(>.pivot-shorts), ytm-pivot-bar-renderer-content[pivot-bar-item-id="pivot-shorts"] { display: none !important; height: 0 !important; }';
                        document.documentElement.appendChild(shortsStyle);
                    }
                } else {
                    if (shortsStyle) shortsStyle.remove();
                }

                // Check if hideSubscriptions needs to be applied/removed
                var hideSub = window.__hideSubscriptions === true;
                var subStyle = document.getElementById('yt-audio-air-hide-subscriptions');
                if (hideSub) {
                    if (!subStyle) {
                        subStyle = document.createElement('style');
                        subStyle.id = 'yt-audio-air-hide-subscriptions';
                        subStyle.textContent = 'a[href*="/feed/subscriptions"], ytm-pivot-bar-item-renderer:has(>.pivot-subscriptions), ytm-pivot-bar-renderer-content[pivot-bar-item-id="pivot-subscriptions"], html[data-ytv-sub="true"] ytm-browse, html[data-ytv-sub="true"] ytm-single-column-browse-results-renderer, html[data-ytv-sub="true"] ytm-section-list-renderer { display: none !important; height: 0 !important; }';
                        document.documentElement.appendChild(subStyle);
                    }
                } else {
                    if (subStyle) subStyle.remove();
                }

                var videos = document.querySelectorAll('video');
                if (videos.length === 0) return;
                var video = videos[0];

                var isAd = false;
                if (window.__premiumUser === true) {
                    isAd = false;
                } else {
                    if (document.querySelector('.ad-showing, .ad-interrupting') !== null) {
                        isAd = true;
                    }
                    var adOverlay = document.querySelector('.ytp-ad-player-overlay, .ytp-ad-overlay-container, .ytm-ad-overlay-renderer');
                    if (adOverlay && adOverlay.offsetHeight > 0) {
                        isAd = true;
                    }
                    var skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button-slot button, .ytp-ad-skip-button-slot, .ytp-ad-skip-button-container, .ytp-ad-skip-button-container button, .ytm-biz-skip-ad-button');
                    if (skipBtn && skipBtn.offsetHeight > 0) {
                        isAd = true;
                    }
                }

                if (isAd) {
                    videos.forEach(function(v) {
                        if (!v.muted) {
                            v.muted = true;
                            wasAdActive = true;
                        }
                        if (v.playbackRate !== 16) {
                            v.playbackRate = 16;
                        }
                        if (isFinite(v.duration) && v.currentTime < v.duration - 0.2) {
                            v.currentTime = v.duration - 0.1;
                        }
                    });
                    if (skipBtn && skipBtn.offsetHeight > 0) {
                        skipBtn.click();
                    }
                } else {
                    videos.forEach(function(v) {
                        if (v.playbackRate === 16) {
                            v.playbackRate = 1;
                        }
                        if (wasAdActive) {
                            v.muted = false;
                        }
                        // Force-unmute on watch pages (defeats YouTube's own mute policy)
                        var isWatch = window.location.pathname.indexOf('/watch') === 0;
                        if (isWatch && v.muted && !v.paused) {
                            v.muted = false;
                        }
                    });
                    if (wasAdActive) {
                        wasAdActive = false;
                    }
                }
                
                // Force low quality (144p) to save memory and CPU
                if (typeof video.dataset.qualityForced === 'undefined') {
                    var moviePlayer = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                    if (moviePlayer) {
                        if (typeof moviePlayer.setPlaybackQualityRange === 'function') {
                            moviePlayer.setPlaybackQualityRange('tiny');
                        }
                        if (typeof moviePlayer.setPlaybackQuality === 'function') {
                            moviePlayer.setPlaybackQuality('tiny');
                        }
                        video.dataset.qualityForced = 'true';
                    }
                }

                if (!video.playsInline) video.playsInline = true;
                if (!video.disableRemotePlayback) video.disableRemotePlayback = true;

                // Apply loop setting
                if (video.loop !== (window.__loopPlayback === true)) {
                    video.loop = window.__loopPlayback === true;
                }

                var videos = document.querySelectorAll('video');
                var video = videos.length > 0 ? videos[0] : null;

                /* Autoplay & UI activator on watch pages */
                var isWatchPage = window.location.pathname.indexOf('/watch') === 0;
                if (isWatchPage && !isAd && video) {
                    if (window.__needsAutoplay && video.paused) {
                        video.muted = false;
                        video.play().catch(function(e) {});
                        var playBtn = document.querySelector('button.player-control-play, .player-play-button');
                        if (playBtn && playBtn.offsetHeight > 0) playBtn.click();
                    } else if (!video.paused) {
                        window.__needsAutoplay = false;
                    }
                }

                // Extract video playing state & attach event listeners
                var isPlaying = false;
                if (video) {
                    isPlaying = (!video.paused && !video.ended);
                    if (!video.__bleListenersAttached) {
                        video.__bleListenersAttached = true;
                        ['play', 'playing', 'pause', 'ended'].forEach(function(evtName) {
                            video.addEventListener(evtName, function() {
                                globalUpdate();
                            });
                        });
                    }
                } else {
                    var pauseBtn = document.querySelector('button[aria-label="Pause"], button[aria-label="Pause video"], .player-control-play[aria-label*="Pause"]');
                    if (pauseBtn) isPlaying = true;
                }

                // Extract track metadata dynamically for BLE sync
                var metaTitle = '';
                var metaArtist = '';

                // 1. Try DOM title elements first
                var titleEl = document.querySelector('h1.slim-video-information-title, .slim-video-metadata-title, .watch-headline h1, ytm-slim-owner-renderer + h1, .ytm-watch-title, h1, .slim-video-information-title-text');
                if (titleEl && titleEl.innerText && titleEl.innerText.trim().length > 0) {
                    metaTitle = titleEl.innerText.trim();
                }

                // 2. Fallback to document.title
                if (!metaTitle || metaTitle.toLowerCase() === 'youtube') {
                    var rawTitle = document.title || '';
                    rawTitle = rawTitle.replace(/^(\\(\\d+\\)\\s*)?/, '').replace(/\\s*-\\s*YouTube$/gi, '').trim();
                    if (rawTitle.indexOf(' - ') !== -1) {
                        var parts = rawTitle.split(' - ');
                        metaTitle = parts[0].trim();
                        metaArtist = parts.slice(1).join(' - ').trim();
                    } else if (rawTitle.length > 0 && rawTitle.toLowerCase() !== 'youtube') {
                        metaTitle = rawTitle;
                    }
                }

                // 3. Extract channel / artist from DOM elements
                var artistEl = document.querySelector('.slim-owner-icon-and-title .slim-owner-name, ytm-slim-owner-renderer .slim-owner-name, .owner-name, .slim-owner-name, a[href*="/@"], .slim-owner-channel-name, .c3-profile-link, ytm-owner-renderer .slim-owner-name');
                if (artistEl && artistEl.innerText && artistEl.innerText.trim().length > 0) {
                    metaArtist = artistEl.innerText.trim();
                }

                // 4. Dynamic artist fallback from title separators if channel element is missing
                if (!metaArtist || metaArtist.toLowerCase() === 'youtube') {
                    if (metaTitle.indexOf(' - ') !== -1) {
                        var parts = metaTitle.split(' - ');
                        metaArtist = parts[0].trim();
                    } else if (metaTitle.indexOf(' | ') !== -1) {
                        var parts = metaTitle.split(' | ');
                        metaArtist = parts[1].trim();
                    } else if (metaTitle.indexOf(' ~ ') !== -1) {
                        var parts = metaTitle.split(' ~ ');
                        metaArtist = parts[0].trim();
                    } else {
                        metaArtist = metaTitle; // Dynamic fallback to current playing video title!
                    }
                }

                if (!metaTitle) metaTitle = 'YT Audio Air';
                if (!metaArtist) metaArtist = metaTitle;

                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bleMetadata) {
                    window.webkit.messageHandlers.bleMetadata.postMessage({
                        title: metaTitle,
                        artist: metaArtist,
                        isPlaying: isPlaying,
                        currentTime: video && isFinite(video.currentTime) ? video.currentTime : 0,
                        duration: video && isFinite(video.duration) ? video.duration : 0
                    });
                }
            }

            setInterval(globalUpdate, 300);

            // Refresh player state after SPA navigation and flag autoplay
            document.addEventListener('yt-navigate-finish', () => {
                if (window.location.pathname.indexOf('/watch') === 0) {
                    window.__needsAutoplay = true;
                } else {
                    window.__needsAutoplay = false;
                }
                var v = document.querySelector('video');
                if (v) delete v.dataset.qualityForced;
                if (transport.busy) releaseTransport(transport.waiting);
                var evt = new MouseEvent('mousemove', { bubbles: true, cancelable: true, clientX: 100, clientY: 100 });
                document.dispatchEvent(evt);
            });
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: optimizationJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
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
            contentRect: NSRect(x: -20000, y: -20000, width: 375, height: 550),
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
        
        let hostingView = NSHostingView(rootView: ContentView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 375, height: 550)
        hostingView.autoresizingMask = [.width, .height]
        
        playerWindow.contentView = hostingView
        playerWindow.orderBack(nil)
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
        return playerWindow != nil && playerWindow.frame.origin.x > -10000
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
        
        playerWindow.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
        playerWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // The WebView stays offscreen during background playback. Redraw its
        // existing layers on reveal without reloading or disturbing playback.
        playerWindow.contentView?.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()
        webView.needsDisplay = true
        webView.layer?.setNeedsDisplay()
        playerWindow.displayIfNeeded()
        
        startMonitoringEvents()
    }
    
    func hideWindow() {
        playerWindow.setFrame(NSRect(x: -20000, y: -20000, width: 375, height: 550), display: true)
        if let appIcon = NSImage(named: "AppIconImage") {
            statusItem?.button?.image = menuIconImage(from: appIcon)
        }
        stopMonitoringEvents()
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
                    "currentTime": currentTime,
                    "duration": duration
                ]
            )
            let volume = getMacMasterVolume()
            BLEMediaServer.shared.broadcastMetadata(title: title, artist: artist, isPlaying: isPlaying, volume: volume)
        }
    }

    private func getMacMasterVolume() -> Int {
        let script = "output volume of (get volume settings)"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let descriptor = appleScript.executeAndReturnError(&error)
            if error == nil {
                return Int(descriptor.int32Value)
            }
        }
        return 50
    }
    
    // MARK: - Remote BLE Media Commands

    func seek(to seconds: Double) {
        guard seconds.isFinite, let wv = webView else { return }
        let time = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), max(0, seconds))
        wv.evaluateJavaScript("""
        (function() {
            var v = document.querySelector('video') || document.querySelector('.html5-main-video');
            if (v && isFinite(v.duration)) v.currentTime = Math.min(\(time), v.duration);
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
            let js = """
            (function() {
                var v = document.querySelector('video') || document.querySelector('.html5-main-video');
                if (v) {
                    if (v.paused) {
                        v.play().catch(function(e) {});
                    } else {
                        v.pause();
                    }
                } else {
                    var btn = document.querySelector('button.player-control-play, .player-play-button');
                    if (btn) btn.click();
                }
            })();
            """
            wv.evaluateJavaScript(js, completionHandler: nil)
            
        case .nextTrack:
            let js = """
            (function() {
                window.__needsAutoplay = true;
                if (typeof window.__ytAudioAirNavigate === 'function') {
                    window.__ytAudioAirNavigate(1);
                } else {
                    if (!Array.isArray(window.__ytAudioAirBootstrapTransport)) window.__ytAudioAirBootstrapTransport = [];
                    if (window.__ytAudioAirBootstrapTransport.length < 16) window.__ytAudioAirBootstrapTransport.push(1);
                }
                setTimeout(function() {
                    var v = document.querySelector('video') || document.querySelector('.html5-main-video');
                    if (v) v.play().catch(function(e) {});
                    if (typeof globalUpdate === 'function') globalUpdate();
                }, 500);
            })();
            """
            wv.evaluateJavaScript(js, completionHandler: nil)
            
        case .previousTrack:
            let js = """
            (function() {
                window.__needsAutoplay = true;
                if (typeof window.__ytAudioAirNavigate === 'function') {
                    window.__ytAudioAirNavigate(-1);
                } else {
                    if (!Array.isArray(window.__ytAudioAirBootstrapTransport)) window.__ytAudioAirBootstrapTransport = [];
                    if (window.__ytAudioAirBootstrapTransport.length < 16) window.__ytAudioAirBootstrapTransport.push(-1);
                }
                setTimeout(function() {
                    var v = document.querySelector('video') || document.querySelector('.html5-main-video');
                    if (v) v.play().catch(function(e) {});
                    if (typeof globalUpdate === 'function') globalUpdate();
                }, 500);
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
        }
    }
}
