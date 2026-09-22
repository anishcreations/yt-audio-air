const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

// Exercise the actual injected script, not a second implementation of it.
const script = fs.readFileSync(path.join(__dirname, '../yt-audio-air/Playback.js'), 'utf8');

function fixture({ playlist = true, panel = true, randomize = false, ids = ['a', 'b', 'c'], index = 0 } = {}) {
    const state = { id: ids[index], index, ad: false, nativeNext: 0, clicks: [], skipClicks: 0, timers: [], events: {}, metadata: [], now: 10000, hasVideo: true, playCalls: 0, pauseCalls: 0, buttonClicks: 0, attributeWrites: 0, metadataReads: 0, playerAvailable: true };
    class Media {
        constructor() {
            Object.assign(this, { duration: 100, currentTime: 100, ended: true, paused: true, muted: false, playbackRate: 1.5, readyState: 4, seeking: false, dataset: {} });
        }
        addEventListener(event, callback) { (this.listeners ??= {})[event] = callback; }
        play() {
            state.playCalls++;
            this.paused = false;
            this.ended = false;
            this.listeners?.play?.();
            return Promise.resolve();
        }
        pause() { state.pauseCalls++; this.paused = true; this.listeners?.pause?.(); }
    }
    const video = new Media();
    const location = { hostname: 'm.youtube.com', pathname: '/watch', href: `https://m.youtube.com/watch?v=${state.id}${playlist ? '&list=RDmix&index=' + (index + 1) : ''}` };
    const player = {
        isReady: () => true,
        getVideoData: () => ({ video_id: state.id }),
        getPlaylist: () => ids,
        getPlaylistIndex: () => state.index,
        setShuffle: value => { state.nativeShuffle = value; },
        playVideoAt: i => { state.clicks.push(i); },
        nextVideo: () => { state.nativeNext++; },
    };
    const rows = ids.map((id, i) => {
        const link = {
            getAttribute: () => `/watch?v=${id}&list=RDmix&index=${i + 1}`,
            click: () => state.clicks.push(i),
        };
        return {
            querySelector: selector => selector.startsWith('a[') ? link : null,
            hasAttribute: attr => attr === 'selected' && i === index,
            getAttribute: () => null,
        };
    });
    const skip = { disabled: false, getAttribute: () => null, getClientRects: () => [1], click: () => { state.skipClicks++; } };
    const document = {
        title: 'Example - YouTube',
        documentElement: { appendChild() {}, setAttribute() { state.attributeWrites++; } },
        createElement: () => ({}),
        getElementById: id => id === 'movie_player' && state.playerAvailable ? player : null,
        querySelectorAll: selector => selector === 'video' && state.hasVideo ? [video] : [],
        querySelector: selector => {
            if (selector === 'video' || selector === '.html5-main-video') return state.hasVideo ? video : null;
            if (selector.startsWith('h1.')) state.metadataReads++;
            if (selector === 'button.player-control-play, .player-play-button') return { offsetHeight: 20, click: () => { state.buttonClicks++; video.pause(); } };
            if (selector === '.ad-showing, .ad-interrupting') return state.ad ? {} : null;
            if (selector.startsWith('ytm-playlist-panel-renderer')) return playlist && panel ? { querySelectorAll: () => rows } : null;
            if (selector.startsWith('button.ytp-ad-skip-button')) return skip;
            // A visible overlay without an ad state must never authorize seeking.
            if (selector.includes('ad-overlay')) return { offsetHeight: 50 };
            return null;
        },
        addEventListener: (event, fn) => { state.events[event] = fn; },
    };
    const window = { location, __randomizePlayback: randomize, __autoplayNext: true, __loopPlayback: false,
        webkit: { messageHandlers: { bleMetadata: { postMessage: value => state.metadata.push(value) } } } };
    const context = { window, document, HTMLMediaElement: Media, URL, console, isFinite, Date: { now: () => state.now }, Math: Object.create(Math),
        setInterval: fn => { state.tick = fn; }, setTimeout: fn => { let active = true; const timer = () => { if (active) { active = false; fn(); } }; timer.cancel = () => { active = false; }; state.timers.push(timer); return timer; }, clearTimeout: timer => timer?.cancel(), MouseEvent: class {} };
    context.Math.random = () => 0.99;
    vm.createContext(context);
    vm.runInContext(script, context);
    state.end = (target = video) => {
        let stopped = false;
        state.events.ended({ target, stopImmediatePropagation: () => { stopped = true; } });
        return stopped;
    };
    return { state, video, window, player, document };
}

test('My Mix advances to the adjacent playlist entry, never generic recommendations', () => {
    const f = fixture();
    f.window.__ytAudioAirMaintainPlayback(false, true);
    assert.deepEqual(f.state.clicks, [1]);
    assert.equal(f.state.nativeNext, 0);
    f.window.__ytAudioAirMaintainPlayback(false, true);
    assert.deepEqual(f.state.clicks, [1], 'same end event must not advance twice');
});

test('Randomize selects another queue entry; Previous still goes backward', () => {
    const shuffled = fixture({ randomize: true });
    shuffled.window.__ytAudioAirNavigate(1);
    assert.deepEqual(shuffled.state.clicks, [2]);
    const previous = fixture({ randomize: true, index: 2 });
    previous.window.__ytAudioAirNavigate(-1);
    assert.deepEqual(previous.state.clicks, [1]);
});

test('collapsed playlist uses indexed player API and disables native shuffle', () => {
    const f = fixture({ panel: false, index: 1 });
    f.window.__ytAudioAirNavigate(1);
    assert.deepEqual(f.state.clicks, [2]);
    assert.equal(f.state.nativeShuffle, false);
    assert.equal(f.state.nativeNext, 0);
});

test('exhausted playlist never falls back to an unrelated recommendation', () => {
    const f = fixture({ index: 2 });
    f.window.__ytAudioAirNavigate(1);
    for (let i = 0; i < 8 && f.state.timers.length; i++) f.state.timers.shift()();
    assert.deepEqual(f.state.clicks, []);
    assert.equal(f.state.nativeNext, 0);
});

test('outside a playlist the suggested-next behavior remains available', () => {
    const f = fixture({ playlist: false });
    f.window.__ytAudioAirNavigate(1);
    assert.equal(f.state.nativeNext, 1);
});

test('loop wins over autoplay and randomize; autoplay off does not advance', () => {
    const f = fixture({ randomize: true });
    assert.equal(f.window.__ytAudioAirMaintainPlayback(true, true), 'loop');
    assert.equal(f.video.currentTime, 0);
    assert.deepEqual(f.state.clicks, []);
    const stopped = fixture();
    assert.equal(stopped.window.__ytAudioAirMaintainPlayback(false, false), 'stop');
    assert.deepEqual(stopped.state.clicks, []);
});

test('ad completion reaches YouTube; content end still runs queue handling', () => {
    const f = fixture();
    f.state.ad = true;
    assert.equal(f.state.end(), false);
    assert.deepEqual(f.state.clicks, []);
    f.state.ad = false;
    assert.equal(f.state.end(), true);
    assert.deepEqual(f.state.clicks, [1]);
});

test('visible overlay alone does not accelerate, mute or seek content', () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 25, ended: false, paused: false });
    f.state.tick();
    assert.equal(f.video.currentTime, 25);
    assert.equal(f.video.playbackRate, 1.5);
    assert.equal(f.video.muted, false);
    assert.equal(f.state.skipClicks, 0);
});

test('ad skipping restores the pre-ad speed when content resumes', () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 5, ended: false, paused: false });
    f.state.ad = true;
    f.state.tick();
    assert.equal(f.video.playbackRate, 16);
    assert.equal(f.video.muted, true);
    assert.equal(f.state.skipClicks, 1);
    f.state.ad = false;
    f.video.currentTime = 0;
    f.state.tick();
    assert.equal(f.video.playbackRate, 1.5);
    assert.equal(f.video.muted, false);
});

test('unsupported ad seeking and rates do not abort metadata updates', () => {
    const f = fixture();
    f.state.ad = true;
    Object.defineProperty(f.video, 'playbackRate', { get: () => 1, set: () => { throw new Error('unsupported'); } });
    Object.defineProperty(f.video, 'currentTime', { get: () => 5, set: () => { throw new Error('unseekable'); } });
    assert.doesNotThrow(() => f.state.tick());
    assert.equal(f.state.metadata.length, 1);
});

test('Premium mode leaves ad playback untouched and lets ended propagate', () => {
    const f = fixture();
    f.window.__premiumUser = true;
    f.state.ad = true;
    f.state.tick();
    assert.equal(f.video.playbackRate, 1.5);
    assert.equal(f.state.skipClicks, 0);
    assert.equal(f.state.end(), false);
});


test('autoplay issues one play request and never clicks the toggle button afterward', () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 5, ended: false });
    f.window.__needsAutoplay = true;
    f.state.tick();
    assert.equal(f.state.playCalls, 1);
    assert.equal(f.state.buttonClicks, 0);
    assert.equal(f.video.paused, false);
});

test('pause during buffering cancels the pending play request and stays paused', async () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 5, ended: false });
    let finish;
    f.video.play = () => { f.state.playCalls++; return new Promise(resolve => { finish = resolve; }); };
    f.window.__needsAutoplay = true;
    f.state.tick();
    f.state.tick();
    assert.equal(f.state.playCalls, 1);
    f.window.__ytAudioAirSetPlaying(false);
    f.video.paused = false; // Model a delayed media start completing after Pause.
    finish();
    await new Promise(setImmediate);
    f.state.tick();
    assert.equal(f.video.paused, true);
    assert.equal(f.state.playCalls, 1);
    assert.equal(f.window.__needsAutoplay, false);
});

test('rapid Play/Pause/Play keeps the newest play request active', async () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 5, ended: false });
    const finishes = [];
    f.video.play = () => { f.state.playCalls++; return new Promise(resolve => finishes.push(resolve)); };
    f.window.__ytAudioAirSetPlaying(true);
    f.window.__ytAudioAirSetPlaying(false);
    f.window.__ytAudioAirSetPlaying(true);
    assert.equal(finishes.length, 2);
    f.video.paused = false;
    finishes[0]();
    finishes[1]();
    await new Promise(setImmediate);
    assert.equal(f.video.paused, false);
});

test('pausing near the end does not skip or loop the track', () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 99.9, ended: false, paused: true });
    f.window.__ytAudioAirMaintainPlayback(false, true);
    f.window.__ytAudioAirMaintainPlayback(true, true);
    assert.deepEqual(f.state.clicks, []);
    assert.equal(f.state.playCalls, 0);
    assert.equal(f.video.currentTime, 99.9);
});

test('Next never resumes the outgoing paused track while the target loads', () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 5, ended: false, paused: true });
    f.window.__ytAudioAirNavigate(1);
    f.state.tick();
    assert.equal(f.state.playCalls, 0);
    f.state.id = 'b';
    f.state.tick();
    assert.equal(f.state.playCalls, 1);
});

test('duplicate navigation events cannot resume a manually paused track', () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 5, ended: false, paused: true });
    f.state.events['yt-navigate-finish']();
    f.state.tick();
    assert.equal(f.state.playCalls, 0);
});

test('unchanged state is deduplicated and metadata/style scans are throttled', () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 5, ended: false, paused: true });
    for (let i = 0; i < 100; i++) f.state.tick();
    assert.equal(f.state.metadata.length, 1);
    assert.equal(f.state.metadataReads, 1);
    assert.equal(f.state.attributeWrites, 3);
    f.state.now += 1100;
    f.state.tick();
    assert.equal(f.state.metadataReads, 2);
    assert.equal(f.state.metadata.length, 1);
});

test('playback events publish promptly without re-running the ad skipper', () => {
    const f = fixture();
    f.state.ad = true;
    Object.assign(f.video, { currentTime: 5, ended: false, paused: true });
    f.state.tick();
    const skips = f.state.skipClicks;
    f.state.now += 2000;
    f.video.play();
    assert.equal(f.state.skipClicks, skips);
    assert.equal(f.state.metadata.at(-1).isPlaying, true);
});

test('ad seeks are rate limited and never restart an in-flight seek', () => {
    const f = fixture();
    f.state.ad = true;
    let seeks = 0;
    Object.defineProperty(f.video, 'currentTime', { get: () => 5, set: () => { seeks++; } });
    f.state.tick();
    f.state.now += 300;
    f.state.tick();
    assert.equal(seeks, 1);
    f.video.seeking = true;
    f.state.now += 2000;
    f.state.tick();
    assert.equal(seeks, 1);
    f.video.seeking = false;
    f.state.tick();
    assert.equal(seeks, 2);
});

test('ad status hides the ad timeline and clears when content returns', () => {
    const f = fixture();
    f.state.ad = true;
    f.state.tick();
    assert.equal(f.state.metadata.at(-1).isAd, true);
    assert.equal(f.state.metadata.at(-1).duration, 0);
    f.state.ad = false;
    Object.assign(f.video, { currentTime: 5, ended: false });
    f.state.tick();
    assert.equal(f.state.metadata.at(-1).isAd, false);
    assert.equal(f.state.metadata.at(-1).duration, 100);
});

test('removing the video clears stale now-playing state', () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 5, ended: false, paused: false });
    f.state.tick();
    f.state.hasVideo = false;
    f.state.tick();
    assert.equal(f.state.metadata.at(-1).isPlaying, false);
    assert.equal(f.state.metadata.at(-1).duration, 0);
    assert.equal(f.state.metadata.at(-1).title, 'YT Audio Air');
    const count = f.state.metadata.length;
    f.video.listeners.pause();
    assert.equal(f.state.metadata.length, count, 'removed video events must be ignored');
});

test('navigation timeout cannot cause the outgoing track to restart', () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 5, ended: false, paused: true });
    f.window.__ytAudioAirNavigate(1);
    f.state.now += 6000;
    f.state.timers.shift()();
    f.state.tick();
    assert.equal(f.state.playCalls, 0);
});

test('Pause during a track change is respected when the new route arrives', () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 5, ended: false, paused: true });
    f.window.__ytAudioAirNavigate(1);
    f.window.__ytAudioAirSetPlaying(false);
    f.state.id = 'b';
    f.window.location.href = 'https://m.youtube.com/watch?v=b&list=RDmix&index=2';
    f.state.events['yt-navigate-finish']();
    f.state.tick();
    assert.equal(f.state.playCalls, 0);
});

test('a newly played track clears the previous manual pause for end handling', () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 5, ended: false, paused: true });
    f.window.__ytAudioAirSetPlaying(false);
    f.video.paused = false; // YouTube starts playback after the user chooses a track.
    f.state.tick();
    Object.assign(f.video, { currentTime: 100, ended: true, paused: true });
    assert.equal(f.window.__ytAudioAirMaintainPlayback(true, true), 'loop');
});


test('rapid Next waits for actual media readiness, not just a changed video ID', () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 5, ended: false });
    f.window.__ytAudioAirNavigate(1);
    f.window.__ytAudioAirNavigate(1);
    f.state.id = 'b';
    Object.assign(f.video, { readyState: 0, duration: NaN });
    f.state.tick();
    assert.equal(f.window.__ytAudioAirTransport.waiting, false, 'must not drain queue while the new video is empty');
    assert.equal(f.window.__ytAudioAirTransport.busy, true);
    assert.deepEqual(f.state.clicks, [1]);
});

test('temporary player removal cannot acknowledge a Next transition', () => {
    const f = fixture();
    f.window.__ytAudioAirNavigate(1);
    f.window.__ytAudioAirNavigate(1);
    f.state.playerAvailable = false;
    f.window.location.href = 'https://m.youtube.com/watch?v=b&list=RDmix&index=2';
    f.state.events['yt-navigate-finish']();
    assert.equal(f.window.__ytAudioAirTransport.waiting, false);
    assert.equal(f.window.__ytAudioAirTransport.busy, true);
    assert.deepEqual(f.state.clicks, [1]);
});

test('queued Next ignores a stale selected playlist row after the first track loads', () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 5, ended: false });
    f.window.__ytAudioAirNavigate(1);
    f.window.__ytAudioAirNavigate(1);
    f.state.id = 'b';
    f.state.index = 1;
    f.state.tick();
    // DOM still marks row a as selected, but the player has now loaded b.
    const timers = f.state.timers.splice(0);
    timers.forEach(timer => timer());
    assert.deepEqual(f.state.clicks, [1, 2]);
});

test('empty media reports loading instead of an active Pause button at 0:00', () => {
    const f = fixture();
    Object.assign(f.video, { readyState: 0, duration: NaN, ended: false, paused: false });
    f.state.tick();
    assert.equal(f.state.metadata.at(-1).isLoading, true);
    assert.equal(f.state.metadata.at(-1).isPlaying, false);
    assert.equal(f.state.metadata.at(-1).duration, 0);
    Object.assign(f.video, { readyState: 4, duration: 100 });
    f.state.tick();
    assert.equal(f.state.metadata.at(-1).isLoading, false);
    assert.equal(f.state.metadata.at(-1).isPlaying, true);
});

test('failed navigation clears queued skips and reports a recoverable error', () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 5, ended: false });
    f.window.__ytAudioAirNavigate(1);
    f.window.__ytAudioAirNavigate(1);
    f.state.hasVideo = false;
    f.state.now += 13000;
    f.state.timers.shift()();
    assert.equal(f.window.__ytAudioAirTransport.busy, false);
    assert.equal(f.window.__ytAudioAirTransport.queue.length, 0);
    assert.equal(f.state.metadata.at(-1).isLoading, false);
    assert.match(f.state.metadata.at(-1).playbackError, /did not load/);
    assert.equal(f.state.metadata.at(-1).isPlaying, false);
    assert.deepEqual(f.state.clicks, [1]);
});

test('a long ad does not time out navigation or unleash the queued skips', () => {
    const f = fixture();
    f.window.__ytAudioAirNavigate(1);
    f.window.__ytAudioAirNavigate(1);
    f.state.ad = true;
    f.state.now += 30000;
    f.state.timers.shift()();
    assert.equal(f.window.__ytAudioAirTransport.busy, true);
    assert.equal(f.window.__ytAudioAirTransport.queue.length, 1);
    assert.equal(f.window.__ytAudioAirTransport.error, null);
});

test('buffering player state cannot release the queue even with old media data present', () => {
    const f = fixture();
    Object.assign(f.video, { currentTime: 5, ended: false });
    f.window.__ytAudioAirNavigate(1);
    f.window.__ytAudioAirNavigate(1);
    f.state.id = 'b';
    f.player.getPlayerState = () => 3;
    f.state.tick();
    assert.equal(f.window.__ytAudioAirTransport.waiting, false);
    assert.equal(f.window.__ytAudioAirTransport.queue.length, 1);
    assert.deepEqual(f.state.clicks, [1]);
});

test('a known playlist boundary stops quietly without a false load error', () => {
    const f = fixture({ index: 2 });
    assert.equal(f.window.__ytAudioAirNavigate(1), 'end-of-playlist');
    assert.equal(f.window.__ytAudioAirTransport.error, null);
    assert.equal(f.window.__ytAudioAirTransport.busy, false);
});
