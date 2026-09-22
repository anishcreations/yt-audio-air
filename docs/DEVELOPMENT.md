# Code layout and checks

- `yt-audio-air/yt_audio_airApp.swift`: app lifecycle, window, WebKit bridge, and native commands.
- `yt-audio-air/Playback.js`: injected playback engine, playlist navigation, ad handling, page styling, and metadata publishing. Xcode copies this resource into the app bundle.
- `yt-audio-air/ContentView.swift`: native player, ad status, and settings UI.
- `yt-audio-air/SystemVolume.swift`: cached Core Audio volume reads, avoiding AppleScript during playback polling.
- `yt-audio-air/BLEMediaServer.swift`: Mac BLE service and metadata transport.
- `android/app/src/main/`: active Android companion application source.
- `tests/playback.test.cjs`: deterministic tests of the bundled playback engine using media and DOM fixtures.

Run playback regressions with `node --test tests/playback.test.cjs`.
Build the Mac app with Xcode or `xcodebuild -project yt-audio-air.xcodeproj -scheme yt-audio-air -configuration Debug CODE_SIGNING_ALLOWED=NO build`.
After code changes, run `graphify update .`.

For live verification, exercise a playlist and My Mix, pause while buffering, skip tracks rapidly, and hide/show the panel. During an ad, confirm the status message appears, seeking is disabled, and content resumes at its original playback speed. Tests use fixtures; YouTube network behavior and DOM changes still require a live check.

For repeated Next, delay the network while pressing Next several times. Confirm each command waits for loaded media, the playlist advances in order, and Loading track appears instead of an active Pause button with an empty timeline. A transition that cannot load should stop the pending queue and offer Refresh player; reaching a known playlist boundary should stop quietly.
