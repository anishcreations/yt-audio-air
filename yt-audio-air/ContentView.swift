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
import WebKit

// MARK: - ContentView (Root Popover View)

struct ContentView: View {
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false
    @State private var pageTitle = "YT Audio Air"
    @State private var showOptions = false
    @State private var isHoveringPlayer = false
    @State private var isWatchPage = false
    @State private var playerIsPlaying = false
    @State private var playbackTime = 0.0
    @State private var playbackDuration = 0.0
    @State private var isSeeking = false
    
    @AppStorage("hideImages") private var hideImages = false
    @AppStorage("grayscale") private var grayscale = false
    @AppStorage("hideHomeFeed") private var hideHomeFeed = true
    @AppStorage("hideShorts") private var hideShorts = true
    @AppStorage("hideSubscriptions") private var hideSubscriptions = true
    @AppStorage("premiumUser") private var premiumUser = false
    @AppStorage("loopPlayback") private var loopPlayback = false
    @AppStorage("autoplayNext") private var autoplayNext = true
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // ── Premium Header ──
                HeaderView(
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    isLoading: $isLoading,
                    pageTitle: $pageTitle,
                    showOptions: $showOptions
                )
                
                // ── WebView ──
                ZStack(alignment: .bottom) {
                    WebViewContainer()
                        .frame(width: 375, height: 480)
                    
                    // Gradient overlay to blend bottom of YouTube feed
                    LinearGradient(
                        gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.85)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 25)
                    .allowsHitTesting(false)

                    if isWatchPage {
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: 38)
                                .allowsHitTesting(false)

                            ZStack(alignment: .bottom) {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        AppDelegate.shared?.handleRemoteCommand(BLEMediaServer.Command.togglePlayPause.rawValue)
                                    }

                                if isHoveringPlayer || isSeeking {
                                    PlayerTransportControls(
                                        isPlaying: playerIsPlaying,
                                        currentTime: $playbackTime,
                                        duration: playbackDuration,
                                        isSeeking: $isSeeking,
                                        loopPlayback: $loopPlayback,
                                        autoplayNext: $autoplayNext
                                    )
                                        .padding(.bottom, 12)
                                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                                }
                            }
                            .frame(height: 211)
                            .onHover { hovering in
                                withAnimation(.easeOut(duration: 0.12)) {
                                    isHoveringPlayer = hovering
                                }
                            }

                            Spacer(minLength: 0)
                                .allowsHitTesting(false)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
                
                // ── Footer ──
                FooterView()
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            )
            
            // ── Centered Glassmorphic Options Popup ──
            if showOptions {
                // Background dark overlay
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            showOptions = false
                        }
                    }
                    .transition(.opacity)
                
                VStack(spacing: 14) {
                    HStack {
                        Text("Options")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                showOptions = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hide Images from Feed")
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.85))
                                Text("(also hides channel profile pictures)")
                                    .font(.system(size: 9, weight: .regular, design: .rounded))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                            Spacer()
                            Toggle("", isOn: $hideImages)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        HStack {
                            Text("Grayscale Mode")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Toggle("", isOn: $grayscale)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        HStack {
                            Text("Hide Home Feed")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Toggle("", isOn: $hideHomeFeed)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        HStack {
                            Text("Hide Shorts Feed")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Toggle("", isOn: $hideShorts)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        HStack {
                            Text("Hide Subscriptions Feed")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Toggle("", isOn: $hideSubscriptions)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        HStack {
                            Text("YouTube Premium User")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Toggle("", isOn: $premiumUser)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        HStack {
                            Text("Loop Playback")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Toggle("", isOn: $loopPlayback)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Autoplay Next")
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.85))
                                Text("(Loop takes precedence)")
                                    .font(.system(size: 9, weight: .regular, design: .rounded))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                            Spacer()
                            Toggle("", isOn: $autoplayNext)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        
                        Button(action: {
                            if let url = URL(string: "https://m.youtube.com") {
                                AppDelegate.shared?.webView.load(URLRequest(url: url))
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                showOptions = false
                            }
                        }) {
                            HStack {
                                Image(systemName: "house.fill")
                                    .font(.system(size: 10))
                                Text("Go to Home Feed")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .frame(width: 250)
                .background(
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startNavigationPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowOptions"))) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                showOptions = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PlayerStateUpdated"))) { notification in
            guard let state = notification.userInfo else { return }
            playerIsPlaying = state["isPlaying"] as? Bool ?? false
            if !isSeeking {
                playbackDuration = max(0, (state["duration"] as? NSNumber)?.doubleValue ?? 0)
                playbackTime = min(
                    max(0, (state["currentTime"] as? NSNumber)?.doubleValue ?? 0),
                    max(playbackDuration, 0)
                )
            }
        }
        .onChange(of: loopPlayback) { _ in
            AppDelegate.shared?.playbackPreferencesDidChange()
        }
        .onChange(of: autoplayNext) { _ in
            AppDelegate.shared?.playbackPreferencesDidChange()
        }
    }
    
    private func startNavigationPolling() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            guard let wv = AppDelegate.shared?.webView else { return }
            DispatchQueue.main.async {
                canGoBack = wv.canGoBack
                canGoForward = wv.canGoForward
                isLoading = wv.isLoading
                pageTitle = wv.title ?? "YT Audio Air"
                let watchPage = wv.url?.path.hasPrefix("/watch") ?? false
                isWatchPage = watchPage
                if !watchPage {
                    isHoveringPlayer = false
                    isSeeking = false
                    playbackTime = 0
                    playbackDuration = 0
                }
                
                let hide = UserDefaults.standard.bool(forKey: "hideImages")
                let gray = UserDefaults.standard.bool(forKey: "grayscale")
                let hideHome = UserDefaults.standard.bool(forKey: "hideHomeFeed")
                let hideSh = UserDefaults.standard.bool(forKey: "hideShorts")
                let hideSub = UserDefaults.standard.bool(forKey: "hideSubscriptions")
                let prem = UserDefaults.standard.bool(forKey: "premiumUser")
                let loop = UserDefaults.standard.bool(forKey: "loopPlayback")
                let autoplay = UserDefaults.standard.bool(forKey: "autoplayNext")
                
                wv.evaluateJavaScript("""
                    window.__hideImages = \(hide);
                    window.__grayscale = \(gray);
                    window.__hideHomeFeed = \(hideHome);
                    window.__hideShorts = \(hideSh);
                    window.__hideSubscriptions = \(hideSub);
                    window.__premiumUser = \(prem);
                    window.__loopPlayback = \(loop);
                    window.__autoplayNext = \(autoplay);
                """, completionHandler: nil)
            }
        }
    }
}

// MARK: - Minimal Player Controls

struct PlayerTransportControls: View {
    let isPlaying: Bool
    @Binding var currentTime: Double
    let duration: Double
    @Binding var isSeeking: Bool
    @Binding var loopPlayback: Bool
    @Binding var autoplayNext: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                Text(formatTime(currentTime))
                    .frame(width: 34, alignment: .trailing)

                Slider(
                    value: $currentTime,
                    in: 0...max(duration, 1),
                    onEditingChanged: { editing in
                        isSeeking = editing
                        if !editing { AppDelegate.shared?.seek(to: currentTime) }
                    }
                )
                .tint(.red)
                .disabled(duration <= 0)

                Text(formatTime(duration))
                    .frame(width: 34, alignment: .leading)
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.72))

            HStack(spacing: 10) {
                playbackModeButton(
                    icon: "repeat",
                    label: "Loop Playback",
                    isEnabled: loopPlayback
                ) {
                    loopPlayback.toggle()
                }
                controlButton(icon: "backward.end.fill", label: "Previous", command: .previousTrack)
                controlButton(
                    icon: isPlaying ? "pause.fill" : "play.fill",
                    label: isPlaying ? "Pause" : "Play",
                    command: .togglePlayPause,
                    emphasized: true
                )
                controlButton(icon: "forward.end.fill", label: "Next", command: .nextTrack)
                playbackModeButton(
                    icon: "forward.end.circle",
                    label: "Autoplay Next",
                    isEnabled: autoplayNext
                ) {
                    autoplayNext.toggle()
                }
            }

            if loopPlayback && autoplayNext {
                Text("Loop takes precedence over Autoplay Next")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundColor(.orange.opacity(0.85))
                    .accessibilityLabel("Loop takes precedence over Autoplay Next")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 325)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 8, y: 3)
    }

    private func controlButton(
        icon: String,
        label: String,
        command: BLEMediaServer.Command,
        emphasized: Bool = false
    ) -> some View {
        Button {
            AppDelegate.shared?.handleRemoteCommand(command.rawValue)
        } label: {
            Image(systemName: icon)
                .font(.system(size: emphasized ? 13 : 11, weight: .semibold))
                .foregroundColor(emphasized ? .black : .white)
                .frame(width: emphasized ? 34 : 30, height: emphasized ? 34 : 30)
                .background(
                    Circle()
                        .fill(emphasized ? Color.white : Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private func playbackModeButton(
        icon: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isEnabled ? .white : .white.opacity(0.45))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isEnabled ? Color.red.opacity(0.75) : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isEnabled ? "On" : "Off")
        .help("\(label): \(isEnabled ? "On" : "Off")")
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }
}

// MARK: - HeaderView

struct HeaderView: View {
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var pageTitle: String
    @Binding var showOptions: Bool
    @State private var hoverBtn: Int? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Brand
                HStack(spacing: 7) {
                    Image("AppIconImage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("YT Audio Air")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                        
                        if isLoading {
                            Text("Loading…")
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                        } else if !pageTitle.isEmpty && pageTitle != "YouTube" && pageTitle != "YT Audio Air" {
                            Text(pageTitle)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                                .frame(maxWidth: 150, alignment: .leading)
                        }
                    }
                }
                
                Spacer()
                
                // Navigation Controls
                HStack(spacing: 6) {
                    navButton(icon: "chevron.left", index: 0, enabled: canGoBack) {
                        AppDelegate.shared?.webView.goBack()
                    }
                    navButton(icon: "chevron.right", index: 1, enabled: canGoForward) {
                        AppDelegate.shared?.webView.goForward()
                    }
                    navButton(icon: "arrow.clockwise", index: 2, enabled: true) {
                        AppDelegate.shared?.webView.reload()
                    }
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            showOptions.toggle()
                        }
                    }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(hoverBtn == 3 ? Color.white.opacity(0.15) : Color.white.opacity(0.07))
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.65)) {
                            hoverBtn = hovering ? 3 : nil
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            // Loading progress bar
            if isLoading {
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.22, blue: 0.22),
                                    Color(red: 1.0, green: 0.45, blue: 0.15)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.4, height: 2)
                        .cornerRadius(1)
                        .offset(x: loadingOffset(width: geo.size.width))
                        .animation(
                            Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                            value: isLoading
                        )
                }
                .frame(height: 2)
            }
        }
        .background(Color.black.opacity(0.12))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.04)),
            alignment: .bottom
        )
    }
    
    private func loadingOffset(width: CGFloat) -> CGFloat {
        return isLoading ? width * 0.6 : 0
    }
    
    @ViewBuilder
    private func navButton(icon: String, index: Int, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(enabled ? .white : .white.opacity(0.25))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hoverBtn == index ? Color.white.opacity(0.15) : Color.white.opacity(0.07))
                )
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
        .scaleEffect(hoverBtn == index ? 1.1 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.65)) {
                hoverBtn = hovering ? index : nil
            }
        }
    }
}

// MARK: - FooterView

struct FooterView: View {
    @State private var hoverGH = false
    @State private var hoverKofi = false
    @State private var hoverVersion = false
    
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.04))
            
            HStack {
                // GitHub icon (left)
                Button(action: {
                    if let url = URL(string: "https://github.com/anisharyal09/yt-audio-air") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(hoverGH ? .white.opacity(0.6) : .white.opacity(0.18))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(hoverGH ? Color.white.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { h in
                    withAnimation(.easeOut(duration: 0.15)) { hoverGH = h }
                }
                .help("Open Source & Secure")
                
                Spacer()
                
                // Version (middle)
                Button(action: {
                    if let url = URL(string: "https://github.com/anisharyal09/yt-audio-air/blob/main/CHANGELOG.md") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                        Text("v1.7.0")
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(hoverVersion ? .white.opacity(0.6) : .white.opacity(0.18))
                }
                .buttonStyle(.plain)
                .onHover { h in
                    withAnimation(.easeOut(duration: 0.15)) { hoverVersion = h }
                }
                .help("See changelogs (what's new)")
                
                Spacer()
                
                // Support icon (right)
                Button(action: {
                    if let url = URL(string: "https://anisharyal09.com.np/support?from=yt-audio-air") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("☕")
                        .font(.system(size: 11))
                        .opacity(hoverKofi ? 0.85 : 0.35)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(hoverKofi ? Color.white.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { h in
                    withAnimation(.easeOut(duration: 0.15)) { hoverKofi = h }
                }
                .help("Support Me")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.08))
        }
    }
}

// MARK: - WebViewContainer (NSViewRepresentable)

struct WebViewContainer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        
        if let appDelegate = AppDelegate.shared, let webView = appDelegate.webView {
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(webView)
            
            NSLayoutConstraint.activate([
                webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                webView.topAnchor.constraint(equalTo: container.topAnchor),
                webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // No-op - the WebView remains embedded in the container
    }
}

// MARK: - Visual Effect View (Vibrancy Background)

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

#Preview {
    ContentView()
}
