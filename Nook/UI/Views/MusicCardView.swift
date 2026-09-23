import SwiftUI

struct MusicCardView: View {
    @ObservedObject var musicManager: MusicManager
    /// Fired when the user requests the music source app — either via the
    /// artwork tap or the ⌃O shortcut. The owner wires this up so it can do
    /// additional work (e.g. close the notch) alongside `openSourceApp()`.
    let onOpenSourceApp: () -> Void
    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            artworkColumnWithTooltip

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(primaryLineText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(secondaryLineText)
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    controlsRow
                }

                TimelineView(.animation(minimumInterval: musicManager.playbackState.isPlaying ? 0.2 : 1.0)) { timeline in
                    let elapsedTime = displayedElapsedTime(at: timeline.date)
                    let fraction = progressFraction(for: elapsedTime)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 3)

                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.white.opacity(0.9))
                                .frame(width: max(0, geo.size.width * fraction), height: 3)
                        }
                        .frame(height: 3)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let tapFraction = location.x / geo.size.width
                            let seekTime = max(0, min(tapFraction, 1)) * musicManager.playbackState.duration
                            musicManager.seekTo(seekTime)
                        }
                    }
                    .frame(height: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak musicManager] event in
                guard let musicManager, musicManager.isVisible else { return event }

                // Space: toggle play/pause (skip if text field has focus)
                if event.keyCode == 49 {
                    if let window = event.window,
                       let responder = window.firstResponder,
                       responder.isKind(of: NSTextView.self) || responder.isKind(of: NSTextField.self) {
                        return event
                    }
                    musicManager.togglePlayPause()
                    return nil
                }

                // ⌃⌘ left/right arrows
                let relevantFlags = event.modifierFlags.intersection([.command, .control, .option, .shift])
                if relevantFlags == [.command, .control] {
                    switch event.keyCode {
                    case 123: musicManager.previousTrack(); return nil
                    case 124: musicManager.nextTrack(); return nil
                    default: break
                    }
                }

                // ⌃O: open music app
                if relevantFlags == .control && event.keyCode == 31 {
                    onOpenSourceApp()
                    return nil
                }

                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }
}

private extension MusicCardView {
    var trimmedTitle: String? {
        trimmedPlaybackText(musicManager.playbackState.title)
    }

    var trimmedArtist: String? {
        trimmedPlaybackText(musicManager.playbackState.artist)
    }

    var trimmedAlbum: String? {
        trimmedPlaybackText(musicManager.playbackState.album)
    }

    var primaryLineText: String {
        trimmedTitle
            ?? trimmedArtist
            ?? "Nothing Playing"
    }

    var secondaryLineText: String {
        let secondaryCandidates = [trimmedArtist, trimmedAlbum]
            .compactMap { $0 }
            .filter { $0 != primaryLineText }

        if let secondaryText = secondaryCandidates.first {
            return secondaryText
        }

        return "Unknown Artist"
    }

    var artworkColumn: some View {
        Button(action: onOpenSourceApp) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image = musicManager.albumArt {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: musicManager.fallbackSymbolName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if let sourceApp = musicManager.sourceApp, let icon = sourceApp.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .padding(2)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
    }

    private var artworkColumnWithTooltip: some View {
        artworkColumn
            .shortcutTooltip("⌃O")
    }

    var controlsRow: some View {
        HStack(spacing: 6) {
            TransportButton(
                systemName: "backward.fill",
                shortcut: "⌃⌘←",
                action: musicManager.previousTrack
            )

            TransportButton(
                systemName: musicManager.playbackState.isPlaying ? "pause.fill" : "play.fill",
                shortcut: "Space",
                isPrimary: true,
                action: {
                    musicManager.togglePlayPause(displayedTime: displayedElapsedTime(at: Date()))
                }
            )

            TransportButton(
                systemName: "forward.fill",
                shortcut: "⌃⌘→",
                action: musicManager.nextTrack
            )
        }
    }

    func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = max(Int(time.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func displayedElapsedTime(at date: Date) -> TimeInterval {
        let state = musicManager.playbackState
        guard state.isPlaying else {
            return clampedElapsedTime(state.currentTime, duration: state.duration)
        }

        let delta = max(0, date.timeIntervalSince(state.lastUpdated))
        return clampedElapsedTime(state.currentTime + (delta * state.playbackRate), duration: state.duration)
    }

    func progressFraction(for elapsedTime: TimeInterval) -> Double {
        guard musicManager.playbackState.duration > 0 else { return 0 }
        return min(max(elapsedTime / musicManager.playbackState.duration, 0), 1)
    }

    func clampedElapsedTime(_ elapsedTime: TimeInterval, duration: TimeInterval) -> TimeInterval {
        guard duration > 0 else { return max(0, elapsedTime) }
        return min(max(0, elapsedTime), duration)
    }

    func trimmedPlaybackText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Shortcut Tooltip

private struct ShortcutTooltip: ViewModifier {
    let shortcut: String?

    @State private var showTooltip = false
    @State private var hoverTask: DispatchWorkItem?
    @State private var hoverPoint: CGPoint = .zero

    func body(content: Content) -> some View {
        if let shortcut {
            content
                .overlay(alignment: .topLeading) {
                    if showTooltip {
                        Text(shortcut)
                            .fixedSize()
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.black.opacity(0.65))
                            )
                            .offset(x: hoverPoint.x, y: hoverPoint.y + 16)
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hoverPoint = point
                        hoverTask?.cancel()
                        let task = DispatchWorkItem {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showTooltip = true
                            }
                        }
                        hoverTask = task
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
                    case .ended:
                        hoverTask?.cancel()
                        hoverTask = nil
                        withAnimation(.easeInOut(duration: 0.1)) {
                            showTooltip = false
                        }
                    }
                }
        } else {
            content
        }
    }
}

private extension View {
    func shortcutTooltip(_ shortcut: String) -> some View {
        modifier(ShortcutTooltip(shortcut: shortcut))
    }
}

// MARK: - Transport Button

private struct TransportButton: View {
    let systemName: String
    let shortcut: String?
    var isPrimary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: isPrimary ? 10 : 8, weight: .semibold))
                .foregroundColor(.white.opacity(isPrimary ? 0.98 : 0.82))
                .frame(width: isPrimary ? 22 : 18, height: isPrimary ? 22 : 18)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isPrimary ? 0.15 : 0.05))
                )
        }
        .buttonStyle(.plain)
        .modifier(ShortcutTooltip(shortcut: shortcut))
    }
}
