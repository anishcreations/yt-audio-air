(function() {
    if (window.location.hostname !== 'youtube.com' && !window.location.hostname.endsWith('.youtube.com')) return;
    if (window.__ytAudioAirOpt) return;
    window.__ytAudioAirOpt = true;

    if (typeof window.__needsAutoplay === 'undefined') {
        window.__needsAutoplay = false;
    }

    var playRequests = new WeakMap();
    var manuallyPaused = false;
    var autoplaySourceId = null;
    function requestPlay(video) {
        if (playRequests.has(video)) return;
        var request = { cancelled: false };
        playRequests.set(video, request);
        function finished() {
            if (playRequests.get(video) !== request) return;
            if (request.cancelled) video.pause();
            playRequests.delete(video);
        }
        try {
            video.muted = false;
            Promise.resolve(video.play()).then(finished, finished);
        } catch (_) { finished(); }
    }

    window.__ytAudioAirSetPlaying = function(playing) {
        var video = document.querySelector('video');
        if (!video) return;
        var pending = playRequests.get(video);
        var shouldPlay = typeof playing === 'boolean' ? playing : (video.paused && (!pending || pending.cancelled));
        // A manual pause must cancel pending autoplay, including a play()
        // promise that only resolves after network buffering finishes.
        window.__needsAutoplay = false;
        manuallyPaused = !shouldPlay;
        autoplaySourceId = null;
        if (shouldPlay) {
            if (pending && pending.cancelled) playRequests.delete(video);
            requestPlay(video);
        } else {
            if (pending) pending.cancelled = true;
            video.pause();
        }
        publishPlayerState(video, isAdPlaying());
    };

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
    transport.error = null;
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

    function isAdPlaying() {
        return document.querySelector('.ad-showing, .ad-interrupting') !== null;
    }

    function mediaReady(video) {
        return !!video && !video.error && video.readyState >= 2 && video.duration > 0;
    }

    function transitionReady() {
        var video = document.querySelector('video');
        var player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
        if (!player || !mediaReady(video) || video.ended || video.seeking || isAdPlaying()) return false;
        if (typeof player.getPlayerState === 'function') {
            try {
                var playerState = player.getPlayerState();
                if (playerState === -1 || playerState === 0 || playerState === 3) return false;
            } catch (_) { return false; }
        }
        var changedMedia = video !== transport.startingMedia ||
            (video.currentSrc && video.currentSrc !== transport.startingSource);
        var id = null;
        if (typeof player.getVideoData === 'function') {
            try { id = player.getVideoData().video_id; } catch (_) {}
        } else if (changedMedia) {
            id = new URL(window.location.href).searchParams.get('v');
        }
        // A changed URL or a temporarily missing player is not confirmation
        // that YouTube has rebuilt its media element and playlist controls.
        if (!id) return false;
        if (transport.targetVideoId && id !== transport.targetVideoId) return false;
        if (id === transport.startingVideoId && !changedMedia && window.location.href === transport.startingURL) return false;
        return true;
    }

    function failTransport(message) {
        clearTimeout(transport.timer);
        transport.timer = null;
        transport.busy = false;
        transport.waiting = false;
        transport.activeDirection = 0;
        transport.queue = [];
        transport.retries = 0;
        transport.error = message;
        window.__needsAutoplay = false;
        publishPlayerState(document.querySelector('video'), isAdPlaying());
    }

    // Choose an explicit queue entry: nextVideo() can leave a Mix for
    // recommendations, or honor YouTube's independent shuffle setting.
    function playlistTarget(player, direction) {
        var pageURL = new URL(window.location.href);
        var listId = pageURL.searchParams.get('list');
        var panel = document.querySelector('ytm-playlist-panel-renderer, ytd-playlist-panel-renderer');
        if (!listId && !panel) return null;

        var entries = [];
        var selectedIndex = -1;
        if (panel) {
            var rows = panel.querySelectorAll('ytm-playlist-panel-video-renderer, ytd-playlist-panel-video-renderer');
            rows.forEach(function(row) {
                var link = row.querySelector('a[href*="watch?"]');
                if (!link) return;
                var url = new URL(link.getAttribute('href'), window.location.href);
                if (!url.searchParams.get('v') || (listId && url.searchParams.get('list') !== listId)) return;
                if (row.hasAttribute('selected') || row.getAttribute('aria-current') === 'true' ||
                    row.querySelector('[aria-current="true"]')) selectedIndex = entries.length;
                entries.push({ id: url.searchParams.get('v'), url: url.href, link: link });
            });
        }
        var id = currentVideoId();
        if (selectedIndex >= 0 && entries[selectedIndex].id !== id) selectedIndex = -1;
        if (selectedIndex < 0) {
            var pageIndex = pageURL.searchParams.get('v') === id ? pageURL.searchParams.get('index') : null;
            selectedIndex = entries.findIndex(function(entry) {
                return entry.id === id && (!pageIndex || new URL(entry.url).searchParams.get('index') === pageIndex);
            });
        }
        if (selectedIndex >= 0) {
            var targetIndex = selectedIndex + direction;
            if (window.__randomizePlayback === true && direction > 0) {
                var choices = entries.filter(function(entry) { return entry.id !== id; });
                if (choices.length) return choices[Math.floor(Math.random() * choices.length)];
            } else if (targetIndex >= 0 && targetIndex < entries.length) {
                return entries[targetIndex];
            }
        }

        // The panel can be collapsed or not yet rendered. Use the
        // indexed player queue, retaining list context, as a fallback.
        if (player && typeof player.getPlaylist === 'function' && typeof player.playVideoAt === 'function') {
            try {
                if (typeof player.setShuffle === 'function') player.setShuffle(false);
                var ids = player.getPlaylist();
                var index = typeof player.getPlaylistIndex === 'function' ? player.getPlaylistIndex() : -1;
                if (Array.isArray(ids) && ids.length && ids[index] === id) {
                    var nextIndex = index + direction;
                    if (window.__randomizePlayback === true && direction > 0) {
                        var indexes = ids.map(function(value, i) { return value !== id ? i : -1; })
                            .filter(function(i) { return i >= 0; });
                        if (!indexes.length) return { unavailable: true, endOfPlaylist: true };
                        nextIndex = indexes[Math.floor(Math.random() * indexes.length)];
                    }
                    if (nextIndex >= 0 && nextIndex < ids.length) return { index: nextIndex, id: ids[nextIndex] };
                    return { unavailable: true, endOfPlaylist: true };
                }
            } catch (_) {}
        }
        // Never fall through to a recommendation when a playlist is
        // exhausted or temporarily rebuilding its queue.
        return { unavailable: true };
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
        transport.error = null;

        var player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
        var ready = !!player;
        if (ready && typeof player.isReady === 'function') {
            try { ready = player.isReady(); } catch (_) { ready = false; }
        }
        var button = transportButton(direction);
        var target = playlistTarget(player, direction);

        if (target && target.endOfPlaylist) {
            transport.queue = [];
            window.__needsAutoplay = false;
            releaseTransport(false);
            return 'end-of-playlist';
        }

        if ((target && target.unavailable) || (!target && !ready && !button)) {
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
                failTransport('No playable track available. Try Refresh.');
            }
            return 'waiting';
        }

        transport.retries = 0;
        transport.busy = true;
        transport.activeDirection = direction;
        transport.waiting = false;
        transport.startedAt = Date.now();
        transport.startingVideoId = currentVideoId();
        transport.targetVideoId = target ? target.id : null;
        transport.startingMedia = document.querySelector('video');
        transport.startingSource = transport.startingMedia ? transport.startingMedia.currentSrc : null;
        transport.startingURL = window.location.href;
        autoplaySourceId = transport.startingVideoId;
        manuallyPaused = false;
        window.__needsAutoplay = true;

        var method = direction > 0 ? 'nextVideo' : 'previousVideo';
        var usedPlayerAPI = false;
        var acted = false;

        if (target) {
            try {
                if (target.link) {
                    target.link.click();
                } else {
                    player.playVideoAt(target.index);
                }
                acted = true;
            } catch (_) {}
        }
        if (!target && ready && typeof player[method] === 'function') {
            try {
                player[method]();
                usedPlayerAPI = true;
                acted = true;
            } catch (_) {}
        }
        if (!target && !acted && button) {
            button.click();
            acted = true;
        }
        if (!acted) {
            failTransport('Could not change tracks. Try Refresh.');
            return 'unavailable';
        }
        publishPlayerState(document.querySelector('video'), isAdPlaying());

        clearTimeout(transport.timer);
        function watchdog() {
            if (!transport.busy) return;
            if (transitionReady()) {
                releaseTransport(false);
                return;
            }
            // An ad is a valid loaded transition, not a network timeout.
            // Keep the queue parked until content is ready to accept Next.
            if (isAdPlaying()) transport.startedAt = Date.now();
            if (Date.now() - transport.startedAt < 12000) {
                transport.timer = setTimeout(watchdog, 500);
            } else {
                failTransport('Track did not load. Try Refresh.');
            }
        }
        transport.timer = setTimeout(watchdog, 1500);

        return usedPlayerAPI ? 'player-api' : 'button';
    };

    window.__ytAudioAirMaintainPlayback = function(loopPlayback, autoplayNext) {
        window.__loopPlayback = loopPlayback === true;
        window.__autoplayNext = autoplayNext === true;

        if (window.location.pathname.indexOf('/watch') !== 0) return 'not-watch-page';
        if (isAdPlaying()) return 'ad';
        if (manuallyPaused) return 'paused';
        if (transport.busy || transport.error) return 'navigating';

        var video = document.querySelector('video') || document.querySelector('.html5-main-video');
        if (!video || !isFinite(video.duration) || video.duration <= 0) return 'no-video';

        // Pausing or seeking near the end is not an end-of-track event.
        if (!video.ended) {
            if (video.currentTime < video.duration - 1) window.__ytAudioAirHandledEnd = null;
            return 'playing';
        }

        var endKey = (currentVideoId() || window.location.href) + ':' + Math.round(video.duration * 10);
        if (window.__ytAudioAirHandledEnd === endKey) return 'handled';
        window.__ytAudioAirHandledEnd = endKey;

        if (loopPlayback === true) {
            video.currentTime = 0;
            video.muted = false;
            window.__needsAutoplay = false;
            requestPlay(video);
            return 'loop';
        }
        if (autoplayNext === true) {
            window.__ytAudioAirNavigate(1);
            return 'next';
        }
        return 'stop';
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

    var adPlaybackState = new WeakMap();

    function updateAdPlayback(video, isAd) {
        if (isAd && window.__premiumUser !== true) {
            if (!adPlaybackState.has(video)) {
                adPlaybackState.set(video, { rate: video.playbackRate, muted: video.muted, lastSeek: -Infinity, lastSkip: -Infinity });
            }
            var adState = adPlaybackState.get(video);
            var now = Date.now();
            if (!video.muted) video.muted = true;
            // Some streams reject rate or seek changes. A rejected
            // optimization must not abort metadata or end handling.
            try { if (video.playbackRate !== 16) video.playbackRate = 16; } catch (_) {}
            try {
                if (!video.seeking && now - adState.lastSeek >= 1500 && isFinite(video.duration) && video.duration > 0.2 && video.currentTime < video.duration - 0.2) {
                    adState.lastSeek = now;
                    video.currentTime = video.duration - 0.1;
                }
            } catch (_) {}
            var skip = document.querySelector('button.ytp-ad-skip-button, button.ytp-ad-skip-button-modern, .ytp-ad-skip-button-slot button, .ytm-biz-skip-ad-button');
            if (now - adState.lastSkip >= 1000 && skip && !skip.disabled && skip.getAttribute('aria-disabled') !== 'true' && skip.getClientRects().length > 0) {
                adState.lastSkip = now;
                skip.click();
            }
        } else if (!isAd) {
            var previous = adPlaybackState.get(video);
            if (previous) {
                try { video.playbackRate = previous.rate; } catch (_) {}
                video.muted = previous.muted;
                adPlaybackState.delete(video);
            }
            if (window.location.pathname.indexOf('/watch') === 0 && video.muted && !video.paused) {
                video.muted = false;
            }
        }
    }

    var lastPathname = null;
    function globalUpdate() {
        // Update early path detection attributes
        var pathname = window.location.pathname;
        var isHome = pathname === '/' || pathname === '';
        var isSub = pathname.startsWith('/feed/subscriptions');
        var isWatch = pathname.startsWith('/watch');
        if (pathname !== lastPathname) {
            lastPathname = pathname;
            document.documentElement.setAttribute('data-ytv-home', isHome ? 'true' : 'false');
            document.documentElement.setAttribute('data-ytv-sub', isSub ? 'true' : 'false');
            document.documentElement.setAttribute('data-ytv-watch', isWatch ? 'true' : 'false');
        }

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
        if (videos.length === 0) {
            publishPlayerState(null, false);
            return;
        }
        var video = videos[0];

        // Overlay banners can appear over real content: only the
        // player's ad state authorizes muting, acceleration or seeking.
        var isAd = isAdPlaying();
        updateAdPlayback(video, isAd);

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

        // YouTube can start a newly clicked track itself. Once real playback
        // resumes, a pause from the previous track must not disable looping.
        var pendingPlay = playRequests.get(video);
        if (!video.paused && !video.ended && !(pendingPlay && pendingPlay.cancelled)) manuallyPaused = false;

        // End-of-track behavior is handled explicitly so it remains
        // reliable when YouTube replaces or pauses its media element.
        if (video.loop) video.loop = false;
        window.__ytAudioAirMaintainPlayback(
            window.__loopPlayback === true,
            window.__autoplayNext !== false
        );

        // Do not restart the outgoing track while navigation is buffering.
        var videoId = currentVideoId();
        var awaitingTrack = autoplaySourceId !== null && videoId === autoplaySourceId;
        if (autoplaySourceId !== null && !awaitingTrack) autoplaySourceId = null;
        if (transport.busy && !transport.waiting && transitionReady()) releaseTransport(false);
        var isWatchPage = window.location.pathname.indexOf('/watch') === 0;
        if (isWatchPage && !isAd && !awaitingTrack && !manuallyPaused && !transport.busy && !transport.error && mediaReady(video)) {
            if (window.__needsAutoplay && video.paused) {
                window.__needsAutoplay = false;
                requestPlay(video);
            } else if (!video.paused) {
                window.__needsAutoplay = false;
            }
        }

        if (!video.__bleListenersAttached) {
            video.__bleListenersAttached = true;
            ['play', 'playing', 'pause', 'ended'].forEach(function(evtName) {
                video.addEventListener(evtName, function() {
                    // Events publish state only; they must not re-enter ad
                    // seeking, queue navigation or automatic play requests.
                    if (document.querySelector('video') === video) publishPlayerState(video, isAdPlaying());
                });
            });
        }
        publishPlayerState(video, isAd);
    }

    var metadataCache = null;
    var lastPublishedState = null;
    var lastPublishedTime = -Infinity;
    function trackMetadata(video) {
        if (!video) return { title: 'YT Audio Air', artist: 'YouTube' };
        var now = Date.now();
        var route = window.location.href;
        if (metadataCache && metadataCache.route === route && now - metadataCache.time < 1000) return metadataCache;

        // Extract track metadata dynamically for BLE sync
        var metaTitle = '';
        var metaArtist = '';

        // 1. Try DOM title elements first
        var titleEl = document.querySelector('h1.slim-video-information-title, .slim-video-metadata-title, .watch-headline h1, ytm-slim-owner-renderer + h1, .ytm-watch-title, h1, .slim-video-information-title-text');
        if (titleEl && titleEl.textContent && titleEl.textContent.trim().length > 0) {
            metaTitle = titleEl.textContent.trim();
        }

        // 2. Fallback to document.title
        if (!metaTitle || metaTitle.toLowerCase() === 'youtube') {
            var rawTitle = document.title || '';
            rawTitle = rawTitle.replace(/^(\(\d+\)\s*)?/, '').replace(/\s*-\s*YouTube$/gi, '').trim();
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
        if (artistEl && artistEl.textContent && artistEl.textContent.trim().length > 0) {
            metaArtist = artistEl.textContent.trim();
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

        metadataCache = { title: metaTitle, artist: metaArtist, route: route, time: now };
        return metadataCache;
    }

    function publishPlayerState(video, isAd) {
        var metadata = trackMetadata(video);
        var ready = mediaReady(video);
        var loading = !transport.error && !isAd && window.location.pathname.indexOf('/watch') === 0 && (transport.busy || !ready);
        var state = {
            title: metadata.title,
            artist: metadata.artist,
            isPlaying: ready && !loading && !transport.error && !video.paused && !video.ended,
            isAd: isAd,
            isLoading: loading,
            playbackError: transport.error || '',
            currentTime: ready && !loading && !isAd && isFinite(video.currentTime) ? video.currentTime : 0,
            duration: ready && !loading && !isAd && isFinite(video.duration) ? video.duration : 0
        };
        var now = Date.now();
        if (lastPublishedState && state.title === lastPublishedState.title && state.artist === lastPublishedState.artist &&
            state.isPlaying === lastPublishedState.isPlaying && state.isAd === lastPublishedState.isAd &&
            state.isLoading === lastPublishedState.isLoading && state.playbackError === lastPublishedState.playbackError && state.duration === lastPublishedState.duration) {
            if (state.currentTime === lastPublishedState.currentTime || now - lastPublishedTime < 500) return;
        }

        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bleMetadata) {
            lastPublishedState = state;
            lastPublishedTime = now;
            window.webkit.messageHandlers.bleMetadata.postMessage(state);
        }
    }

    setInterval(globalUpdate, 300);

    // Intercept the media end before YouTube's own handlers can stop or
    // advance it. The app's explicit loop/autoplay preferences win.
    document.addEventListener('ended', function(event) {
        if (!(event.target instanceof HTMLMediaElement)) return;
        if (isAdPlaying()) return;
        if (event.target !== document.querySelector('video')) return;
        var shouldHandle = window.__loopPlayback === true || window.__autoplayNext !== false;
        if (!shouldHandle) return;
        event.stopImmediatePropagation();
        window.__ytAudioAirMaintainPlayback(
            window.__loopPlayback === true,
            window.__autoplayNext !== false
        );
    }, true);

    // Refresh player state after SPA navigation and flag autoplay
    var lastNavigationURL = window.location.href;
    document.addEventListener('yt-navigate-finish', () => {
        if (window.location.href === lastNavigationURL) return;
        lastNavigationURL = window.location.href;
        metadataCache = null;
        window.__needsAutoplay = !manuallyPaused && window.location.pathname.indexOf('/watch') === 0;
        var v = document.querySelector('video');
        if (v) delete v.dataset.qualityForced;
        if (transport.busy && !transport.waiting && transitionReady()) releaseTransport(false);
    });
})();
