import Combine
import ImageIO
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct SessionListView: View {
    @ObservedObject var sessionMonitor: SessionMonitor
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var musicManager: MusicManager
    @ObservedObject var performanceMonitor: PerformanceMonitor
    let isPerformanceMonitorEnabled: Bool
    @AppStorage(AppSettings.musicAbovePerformanceKey) private var musicAbovePerformance: Bool = false

    @State private var instanceRowHeight: CGFloat = 0
    @State private var performanceRowHeight: CGFloat = 44
    @State private var musicCardHeight: CGFloat = 0
    @State private var fileShelfHeight: CGFloat = 0
    @State private var cameraHeight: CGFloat = 0

    @AppStorage("cameraEnabled") private var cameraEnabled: Bool = false
    @AppStorage("storageSelectedTab") private var selectedTab: String = "files"
    private var showsMusicCard: Bool { musicManager.isVisible }
    private var showsCamera: Bool { cameraEnabled }

    /// Open the music source app (Apple Music / Spotify / etc.) and dismiss
    /// the notch so the user actually sees the app they just asked for.
    /// `restorePreviousApp` defaults to `false` because activating the music
    /// app is the user's intent — we must not yank focus back to wherever
    /// Nook stole it from.
    private func handleOpenMusicSource() {
        musicManager.openSourceApp()
        viewModel.notchClose()
    }

    private var maxInstancesListHeight: CGFloat {
        InstancesListLayout.maxListHeight(
            rowHeight: instanceRowHeight
        )
    }

    private var resolvedInstancesListMaxHeight: CGFloat? {
        instanceRowHeight > 0 ? maxInstancesListHeight : nil
    }

    private var measuredListHeight: CGFloat? {
        guard instanceRowHeight > 0 else { return nil }

        return InstancesListLayout.listHeight(
            rowHeight: instanceRowHeight,
            sessionCount: sortedInstances.count
        )
    }

    private var appliedInstancesListHeight: CGFloat? {
        guard let measuredListHeight else { return nil }
        return InstancesListLayout.appliedListHeight(
            contentHeight: measuredListHeight,
            maxHeight: maxInstancesListHeight
        )
    }

    var body: some View {
        Group {
            if selectedTab == "notes" {
                QuickNotesFullView(
                    viewModel: viewModel,
                    selectedTab: $selectedTab
                )
            } else {
                HStack(spacing: 8) {
                    StorageShelfColumnView(viewModel: viewModel)
                        .frame(minWidth: 0, maxWidth: .infinity)
                    MediaCameraColumnView(
                        musicManager: musicManager,
                        cameraEnabled: $cameraEnabled,
                        onOpenMusicSource: handleOpenMusicSource
                    )
                    .frame(minWidth: 0, maxWidth: .infinity)
                }
            }
        }
        .frame(height: 148)
        .measureHeight(using: FileShelfHeightKey.self) { fileShelfHeight = $0 }
        .onAppear {
            syncLayoutMetrics()
        }
        .onChange(of: musicManager.isVisible) { _, _ in
            syncLayoutMetrics()
        }
        .onChange(of: fileShelfHeight) { _, _ in
            syncLayoutMetrics()
        }
        .onChange(of: cameraEnabled) { _, _ in
            syncLayoutMetrics()
        }
        .onChange(of: selectedTab) { _, _ in
            syncLayoutMetrics()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Text("No sessions")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.58))

            Text("Run claude in terminal or start a codex session")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.26))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 220)
                .padding(.top, 10)
        }
        .multilineTextAlignment(.center)
        .frame(
            maxWidth: .infinity,
            minHeight: InstancesListLayout.emptyStateHeight,
            maxHeight: InstancesListLayout.emptyStateHeight,
            alignment: .center
        )
    }

    // MARK: - Instances List

    /// Priority: active (approval/processing/compacting) > waitingForInput > idle
    /// Secondary sort: by last user message date (stable - doesn't change when agent responds)
    /// Note: approval requests stay in their date-based position to avoid layout shift
    private var sortedInstances: [SessionState] {
        sessionMonitor.instances.sorted { a, b in
            let priorityA = phasePriority(a.phase)
            let priorityB = phasePriority(b.phase)
            if priorityA != priorityB {
                return priorityA < priorityB
            }
            // Sort by last user message date (more recent first)
            // Fall back to lastActivity if no user messages yet
            let dateA = a.lastUserMessageDate ?? a.lastActivity
            let dateB = b.lastUserMessageDate ?? b.lastActivity
            return dateA > dateB
        }
    }

    /// Lower number = higher priority
    /// Approval requests share priority with processing to maintain stable ordering
    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval, .waitingForTerminalApproval, .processing, .compacting: return 0
        case .waitingForInput: return 1
        case .idle, .ended: return 2
        }
    }

    private var instancesList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(sortedInstances.enumerated()), id: \.element.stableId) { index, session in
                        InstanceRow(
                            session: session,
                            onFocus: { focusSession(session) },
                            onChat: { openChat(session) },
                            onArchive: { archiveSession(session) },
                            onApprove: { approveSession(session) },
                            onReject: { rejectSession(session) },
                            onApproveAlways: session.provider == .opencode ? { approveAlwaysSession(session) } : nil,
                            isKeyboardSelected: index == viewModel.keyboardSelectedIndex
                        )
                        .measureHeight(using: InstanceRowHeightKey.self) {
                            if index == 0 {
                                instanceRowHeight = $0
                            }
                        }
                        .id(session.stableId)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: resolvedInstancesListMaxHeight)
            .onChange(of: viewModel.keyboardSelectedIndex) { _, idx in
                guard idx < sortedInstances.count else { return }
                withAnimation(.smooth(duration: 0.2)) {
                    proxy.scrollTo(sortedInstances[idx].stableId, anchor: .center)
                }
            }
            .onReceive(viewModel.$keyboardActivateTrigger) { trigger in
                guard trigger != nil,
                      viewModel.keyboardSelectedIndex >= 0,
                      viewModel.keyboardSelectedIndex < sortedInstances.count else { return }
                openChat(sortedInstances[viewModel.keyboardSelectedIndex])
            }
        }
    }

    // MARK: - Actions

    private func focusSession(_ session: SessionState) {
        guard session.isInTmux else { return }

        Task {
            if let pid = session.pid {
                _ = await YabaiController.shared.focusWindow(forClaudePid: pid)
            } else {
                _ = await YabaiController.shared.focusWindow(forWorkingDirectory: session.cwd)
            }
        }
    }

    private func openChat(_ session: SessionState) {
        viewModel.showChat(for: session)
    }

    private func approveSession(_ session: SessionState) {
        sessionMonitor.approvePermission(sessionId: session.sessionId)
    }

    private func approveAlwaysSession(_ session: SessionState) {
        DebugLog.shared.write("[notch] approveAlwaysSession sessionId=\(session.sessionId) provider=\(session.provider) activePermission=\(session.activePermission != nil)")
        sessionMonitor.approvePermission(sessionId: session.sessionId, always: true)
    }

    private func rejectSession(_ session: SessionState) {
        sessionMonitor.denyPermission(sessionId: session.sessionId, reason: nil)
    }

    private func archiveSession(_ session: SessionState) {
        sessionMonitor.archiveSession(sessionId: session.sessionId)
    }
}

private enum InstancesListLayout {
    static let targetVisibleRows: CGFloat = 3.2
    static let contentSpacing: CGFloat = 6
    static let listRowSpacing: CGFloat = 2
    static let emptyStateHeight: CGFloat = 84

    static func maxListHeight(rowHeight: CGFloat) -> CGFloat {
        listHeight(rowHeight: rowHeight, visibleRows: targetVisibleRows)
    }

    static func listHeight(rowHeight: CGFloat, sessionCount: Int) -> CGFloat {
        listHeight(
            rowHeight: rowHeight,
            visibleRows: min(CGFloat(max(0, sessionCount)), targetVisibleRows)
        )
    }

    static func appliedListHeight(
        contentHeight: CGFloat,
        maxHeight: CGFloat
    ) -> CGFloat {
        min(max(0, contentHeight), max(0, maxHeight))
    }

    private static func listHeight(rowHeight: CGFloat, visibleRows: CGFloat) -> CGFloat {
        let clampedVisibleRows = max(0, visibleRows)
        let visibleRowsHeight = max(0, rowHeight) * clampedVisibleRows
        let visibleSpacingCount = max(0, ceil(clampedVisibleRows) - 1)
        let spacingHeight = listRowSpacing * visibleSpacingCount
        return visibleRowsHeight + spacingHeight
    }
}

private struct InstanceRowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct MusicCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct FileShelfHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CameraHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct PerformanceRowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct MeasuredHeightReader<Key: PreferenceKey>: ViewModifier where Key.Value == CGFloat {
    let onChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: Key.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(Key.self, perform: onChange)
    }
}

private extension View {
    func measureHeight<Key: PreferenceKey>(
        using _: Key.Type,
        _ onChange: @escaping (CGFloat) -> Void
    ) -> some View where Key.Value == CGFloat {
        modifier(MeasuredHeightReader<Key>(onChange: onChange))
    }
}

private extension SessionListView {
    func syncLayoutMetrics() {
        guard viewModel.contentType == .instances else { return }

        if abs(viewModel.instancesPageRowHeight - instanceRowHeight) > 0.5 {
            viewModel.instancesPageRowHeight = instanceRowHeight
        }

        if abs(viewModel.instancesPagePerformanceRowHeight - performanceRowHeight) > 0.5 {
            viewModel.instancesPagePerformanceRowHeight = performanceRowHeight
        }

        if abs(viewModel.instancesPageMusicCardHeight - musicCardHeight) > 0.5 {
            viewModel.instancesPageMusicCardHeight = musicCardHeight
        }

        if abs(viewModel.instancesPageFileShelfHeight - fileShelfHeight) > 0.5 {
            viewModel.instancesPageFileShelfHeight = fileShelfHeight
        }

        if abs(viewModel.instancesPageCameraHeight - cameraHeight) > 0.5 {
            viewModel.instancesPageCameraHeight = cameraHeight
        }
    }
}

// MARK: - Instance Row

struct InstanceRow: View {
    let session: SessionState
    let onFocus: () -> Void
    let onChat: () -> Void
    let onArchive: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void
    /// Optional "Always allow" affordance. When non-nil, the inline approval
    /// buttons render a third red-tinted button that grants a session-wide
    /// allowance. Only wired up for OpenCode sessions.
    let onApproveAlways: (() -> Void)?
    let isKeyboardSelected: Bool

    @State private var isHovered = false
    @State private var isYabaiAvailable = false
    @State private var isConfirmingAlways = false

    private var providerTint: Color {
        SessionLoadingStyle.tint(for: session.provider)
    }

    private var providerLabelForeground: Color {
        switch session.provider {
        case .claude:
            return Color(red: 0.98, green: 0.82, blue: 0.62)
        case .codex:
            return Color(red: 0.80, green: 0.90, blue: 0.98)
        case .opencode:
            return Color(red: 0.72, green: 0.95, blue: 0.72)
        case .cursor:
            return Color(red: 0.86, green: 0.86, blue: 0.84)
        }
    }

    private var providerLabelBackground: Color {
        switch session.provider {
        case .claude:
            return Color(red: 0.85, green: 0.47, blue: 0.34).opacity(0.28)
        case .codex:
            return Color(red: 0.50, green: 0.60, blue: 0.66).opacity(0.40)
        case .opencode:
            return Color(red: 0.40, green: 0.80, blue: 0.40).opacity(0.28)
        case .cursor:
            return Color(red: 0.12, green: 0.12, blue: 0.12).opacity(0.42)
        }
    }

    /// Whether we're showing the approval UI
    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    private var isWaitingForTerminalApproval: Bool {
        session.phase.isWaitingForTerminalApproval
    }

    /// Whether the session is waiting for user input (AskUserQuestion).
    /// Unified across providers: Claude sends status: "waiting_for_input",
    /// OpenCode sends PermissionRequest — both resolve to .waitingForInput.
    private var isWaitingForUserInput: Bool {
        session.phase.isWaitingForInput && isInteractiveTool
    }

    /// Whether the pending tool requires interactive input (not just approve/deny)
    private var isInteractiveTool: Bool {
        guard let toolName = session.pendingToolName else { return false }
        return ToolCallItem.kind(of: toolName) == .askUserQuestion
    }

    /// Status text based on session phase (fallback when no other content)
    private var phaseStatusText: String {
        switch session.phase {
        case .processing:
            return "Processing..."
        case .compacting:
            return "Compacting..."
        case .waitingForInput:
            return "Ready"
        case .waitingForApproval:
            return "Waiting for approval"
        case .waitingForTerminalApproval:
            return "Approval needed in terminal"
        case .idle:
            return "Idle"
        case .ended:
            return "Ended"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // State indicator on left
            stateIndicator
                .frame(width: 14)

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                if isConfirmingAlways {
                    // Confirm mode: show "Patterns" label + allowed patterns
                    Text("Patterns")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    let patterns = session.activePermission?.alwaysPatterns ?? []
                    let text = patterns.count == 1 && patterns[0] == "*"
                        ? "Allow all until restart"
                        : patterns.joined(separator: ", ")
                    MarqueeText(text: text, font: .system(size: 10), color: .white.opacity(0.5))
                        .frame(maxWidth: 200, alignment: .leading)
                } else {
                    HStack(spacing: 6) {
                        Text(session.displayTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(session.provider.displayName)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(providerLabelForeground)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(providerLabelBackground)
                            .clipShape(Capsule())

                        if session.usage.totalTokens > 0 {
                            Text(session.usage.formattedTotal)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }

                    if (isWaitingForApproval || isWaitingForTerminalApproval || isWaitingForUserInput),
                       let toolName = session.pendingToolName {
                        HStack(spacing: 6) {
                            Text(MCPToolFormatter.formatToolName(toolName))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(TerminalColors.amber.opacity(0.9))
                                .fixedSize(horizontal: true, vertical: false)
                            if isInteractiveTool {
                                Text("Needs your input")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.5))
                                    .lineLimit(1)
                            } else if let input = session.pendingToolInput {
                                MarqueeText(
                                    text: input,
                                    font: .system(size: 11),
                                    color: .white.opacity(0.5)
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else if let role = session.lastMessageRole {
                        switch role {
                        case "tool":
                            HStack(spacing: 4) {
                                if let toolName = session.lastToolName {
                                    Text(MCPToolFormatter.formatToolName(toolName))
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                if let input = session.lastMessage {
                                    Text(input)
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.4))
                                        .lineLimit(1)
                                }
                            }
                        case "user":
                            HStack(spacing: 4) {
                                Text("You:")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                                if let msg = session.lastMessage {
                                    Text(msg)
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.4))
                                        .lineLimit(1)
                                }
                            }
                        default:
                            if let msg = session.lastMessage {
                                Text(msg)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.4))
                                    .lineLimit(1)
                            }
                        }
                    } else if let lastMsg = session.lastMessage {
                        Text(lastMsg)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    } else {
                        Text(phaseStatusText)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            // Action icons or approval buttons
            if isWaitingForTerminalApproval || ((isWaitingForApproval || isWaitingForUserInput) && isInteractiveTool) {
                // Interactive tools and terminal-side approval prompts need terminal focus.
                HStack(spacing: 8) {
                    // Go to Terminal button (only if yabai available)
                    if isYabaiAvailable {
                        TerminalButton(
                            isEnabled: session.isInTmux,
                            onTap: { onFocus() }
                        )
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if isWaitingForApproval {
                InlineApprovalButtons(
                    onApprove: onApprove,
                    onReject: onReject,
                    onApproveAlways: onApproveAlways,
                    isConfirmingAlways: $isConfirmingAlways
                )
                .layoutPriority(1)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                HStack(spacing: 8) {
                    // Focus icon (only for tmux instances with yabai)
                    if session.isInTmux && isYabaiAvailable {
                        IconButton(icon: "eye") {
                            onFocus()
                        }
                    }

                    // Archive button - only for idle or completed sessions
                    if session.phase == .idle || session.phase == .waitingForInput {
                        IconButton(icon: "archivebox") {
                            onArchive()
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(count: 1) {
            onChat()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWaitingForApproval)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isKeyboardSelected ? Color.white.opacity(0.08) : (isHovered ? Color.white.opacity(0.06) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isKeyboardSelected ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .task {
            isYabaiAvailable = await WindowFinder.shared.isYabaiAvailable()
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch session.phase {
        case .processing, .compacting:
            ProcessingSpinner(provider: session.provider)
        case .waitingForApproval, .waitingForTerminalApproval:
            ProcessingSpinner(color: TerminalColors.amber)
        case .waitingForInput:
            // Pixel speech bubble (12×12) — visually distinct from the
            // 6×6 idle dot, matches the opencode ask_user_question /
            // Claude Code "Ready for input" state semantically.
            WaitingForInputIcon(size: 12)
        case .idle, .ended:
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 6, height: 6)
        }
    }

}

// MARK: - Inline Approval Buttons

/// Compact inline approval buttons with staggered animation.
/// When the user taps "Always", the buttons swap to Confirm / Cancel
/// (inline, no extra text — notch space is too tight for patterns).
struct InlineApprovalButtons: View {
    let onApprove: () -> Void
    let onReject: () -> Void
    let onApproveAlways: (() -> Void)?
    @Binding var isConfirmingAlways: Bool

    @State private var showDenyButton = false
    @State private var showAllowButton = false
    @State private var showAlwaysButton = false

    init(
        onApprove: @escaping () -> Void,
        onReject: @escaping () -> Void,
        onApproveAlways: (() -> Void)? = nil,
        isConfirmingAlways: Binding<Bool> = .constant(false)
    ) {
        self.onApprove = onApprove
        self.onReject = onReject
        self.onApproveAlways = onApproveAlways
        self._isConfirmingAlways = isConfirmingAlways
    }

    var body: some View {
        // Button row only — patterns info is displayed by the parent (InstanceRow)
        HStack(spacing: 6) {
            if isConfirmingAlways {
                Button {
                    isConfirmingAlways = false
                } label: {
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)

                Button {
                    DebugLog.shared.write("[notch] Confirm tapped")
                    isConfirmingAlways = false
                    onApproveAlways?()
                } label: {
                    Text("Confirm")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.92, green: 0.30, blue: 0.25))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.9))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
            } else {
                Button {
                    onReject()
                } label: {
                    Text("Deny")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(showDenyButton ? 1 : 0)
                .scaleEffect(showDenyButton ? 1 : 0.8)

                Button {
                    onApprove()
                } label: {
                    Text("Allow")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.9))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(showAllowButton ? 1 : 0)
                .scaleEffect(showAllowButton ? 1 : 0.8)

                if onApproveAlways != nil {
                    Button {
                        DebugLog.shared.write("[notch] Always tapped")
                        isConfirmingAlways = true
                    } label: {
                        Text("Always")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 0.92, green: 0.30, blue: 0.25))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.9))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .opacity(showAlwaysButton ? 1 : 0)
                    .scaleEffect(showAlwaysButton ? 1 : 0.8)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.0)) {
                showDenyButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showAllowButton = true
            }
            if onApproveAlways != nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1)) {
                    showAlwaysButton = true
                }
            }
        }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? .white.opacity(0.8) : .white.opacity(0.4))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Compact Terminal Button (inline in description)

struct CompactTerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "terminal")
                    .font(.system(size: 8, weight: .medium))
                Text("Go to Terminal")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isEnabled ? .white.opacity(0.9) : .white.opacity(0.3))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isEnabled ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Terminal Button

struct TerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "terminal")
                    .font(.system(size: 9, weight: .medium))
                Text("Terminal")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isEnabled ? .black : .white.opacity(0.4))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isEnabled ? Color.white.opacity(0.95) : Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - File Shelf Manager

// MARK: - File Thumbnail Loader

final class FileThumbnailLoader: ObservableObject {
    @Published var thumbnail: NSImage?
    private static let cache = NSCache<NSURL, NSImage>()

    init(url: URL) {
        if let cached = Self.cache.object(forKey: url as NSURL) {
            self.thumbnail = cached
            return
        }
        
        // Immediate fallback: system icon so UI is instantly responsive
        self.thumbnail = NSWorkspace.shared.icon(forFile: url.path)
        loadThumbnail(for: url)
    }

    private func loadThumbnail(for url: URL) {
        let targetSize = CGSize(width: 96, height: 96)
        let ext = url.pathExtension.lowercased()

        // Fast path for images via ImageIO (PNG, JPG, HEIC, WEBP, GIF, TIFF, etc.)
        if ["jpg", "jpeg", "png", "heic", "webp", "gif", "tiff", "bmp", "ico"].contains(ext) {
            DispatchQueue.global(qos: .userInteractive).async {
                if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                    let maxDimension = max(targetSize.width, targetSize.height) * 2.0
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceShouldCacheImmediately: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maxDimension
                    ]
                    if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                        let img = NSImage(cgImage: cgThumb, size: NSSize(width: 36, height: 36))
                        Self.cache.setObject(img, forKey: url as NSURL)
                        DispatchQueue.main.async {
                            self.thumbnail = img
                        }
                        return
                    }
                }
                self.requestQuickLook(for: url, targetSize: targetSize)
            }
            return
        }

        // QuickLook Thumbnailing for documents, PDFs, videos, audio, etc.
        requestQuickLook(for: url, targetSize: targetSize)
    }

    private func requestQuickLook(for url: URL, targetSize: CGSize) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: targetSize,
            scale: scale,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            if let cgImage = representation?.cgImage {
                let img = NSImage(cgImage: cgImage, size: NSSize(width: 36, height: 36))
                Self.cache.setObject(img, forKey: url as NSURL)
                DispatchQueue.main.async {
                    self.thumbnail = img
                }
            }
        }
    }
}

// MARK: - Quick Action Types

enum QuickActionType: String, CaseIterable, Identifiable {
    case capture = "capture"
    case lock = "lock"
    case pomodoro = "pomodoro"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .capture: return "Capture"
        case .lock: return "Lock"
        case .pomodoro: return "Pomodoro"
        }
    }
    
    var iconName: String {
        switch self {
        case .capture: return "camera.viewfinder"
        case .lock: return "lock.fill"
        case .pomodoro: return "timer"
        }
    }
}

// MARK: - Pomodoro Manager

enum PomodoroState: Equatable {
    case idle
    case focus(secondsRemaining: Int)
    case breakTime(secondsRemaining: Int)
}

final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()
    
    @Published var state: PomodoroState = .idle
    @AppStorage("pomodoroFocusMinutes") var focusMinutes: Int = 25
    @AppStorage("pomodoroBreakMinutes") var breakMinutes: Int = 5
    
    private var timer: Timer?
    
    private init() {}
    
    var isRunning: Bool {
        if case .idle = state { return false }
        return true
    }
    
    var isBreak: Bool {
        if case .breakTime = state { return true }
        return false
    }
    
    var timeRemainingString: String {
        switch state {
        case .idle:
            return "\(focusMinutes)m"
        case .focus(let s), .breakTime(let s):
            let m = s / 60
            let sec = s % 60
            return String(format: "%02d:%02d", m, sec)
        }
    }
    
    func toggle() {
        if isRunning {
            stop()
        } else {
            startFocus()
        }
    }
    
    func startFocus() {
        state = .focus(secondsRemaining: max(1, focusMinutes) * 60)
        startTimer()
    }
    
    func startBreak() {
        state = .breakTime(secondsRemaining: max(1, breakMinutes) * 60)
        startTimer()
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        state = .idle
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.tick()
        }
    }
    
    private func tick() {
        switch state {
        case .idle:
            timer?.invalidate()
        case .focus(let s):
            if s > 1 {
                state = .focus(secondsRemaining: s - 1)
            } else {
                stop()
                NSSound(named: "Glass")?.play()
            }
        case .breakTime(let s):
            if s > 1 {
                state = .breakTime(secondsRemaining: s - 1)
            } else {
                stop()
                NSSound(named: "Glass")?.play()
            }
        }
    }
}

// MARK: - Quick Action Button View

struct QuickActionButtonView: View {
    let actionType: QuickActionType
    var viewModel: NotchViewModel? = nil
    @ObservedObject private var pomodoro = PomodoroManager.shared
    
    var body: some View {
        Button(action: handleAction) {
            HStack(spacing: 3) {
                Image(systemName: iconName)
                    .font(.system(size: 8.5))
                Text(buttonLabel)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4.5)
            .background(backgroundColor)
            .cornerRadius(7)
        }
        .buttonStyle(.plain)
    }
    
    private var iconName: String {
        switch actionType {
        case .capture:
            return "camera.viewfinder"
        case .lock:
            return "lock.fill"
        case .pomodoro:
            return pomodoro.isBreak ? "cup.and.saucer.fill" : "timer"
        }
    }
    
    private var buttonLabel: String {
        switch actionType {
        case .capture:
            return "Capture"
        case .lock:
            return "Lock"
        case .pomodoro:
            return pomodoro.isRunning ? pomodoro.timeRemainingString : "Pomodoro"
        }
    }
    
    private var textColor: Color {
        switch actionType {
        case .pomodoro:
            if pomodoro.isRunning {
                return pomodoro.isBreak ? Color.green : Color.orange
            }
            return .white.opacity(0.85)
        default:
            return .white.opacity(0.85)
        }
    }
    
    private var backgroundColor: Color {
        if actionType == .pomodoro && pomodoro.isRunning {
            return pomodoro.isBreak ? Color.green.opacity(0.18) : Color.orange.opacity(0.18)
        }
        return Color.white.opacity(0.08)
    }
    
    private func handleAction() {
        switch actionType {
        case .capture:
            // 1. Hide the notch drawer immediately
            viewModel?.notchClose()
            // 2. Open Screenshot utility after notch collapses
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
            }
        case .lock:
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            task.arguments = ["displaysleepnow"]
            try? task.run()
        case .pomodoro:
            pomodoro.toggle()
        }
    }
}

// MARK: - Quick Notes Manager

class QuickNotesManager {
    static let shared = QuickNotesManager()
    
    func exportToAppleNotes(text: String, completion: @escaping (Bool) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(false)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let escaped = trimmed
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\r\n", with: "<br>")
                .replacingOccurrences(of: "\n", with: "<br>")
            
            let scriptSource = """
            tell application "Notes"
                tell default account
                    make new note at folder "Notes" with properties {body: "<div><strong>Notchify Quick Note:</strong></div><div>\(escaped)</div>"}
                end tell
            end tell
            """
            
            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                script.executeAndReturnError(&error)
                let ok = (error == nil)
                DispatchQueue.main.async {
                    completion(ok)
                }
            } else {
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }
}

// MARK: - Quick Notes Full View (2-Column Span)

struct QuickNotesFullView: View {
    var viewModel: NotchViewModel
    @Binding var selectedTab: String
    @ObservedObject var fileManager = FileShelfManager.shared
    @AppStorage("quickActionButton1") private var actionButton1Raw: String = QuickActionType.capture.rawValue
    @AppStorage("quickActionButton2") private var actionButton2Raw: String = QuickActionType.lock.rawValue
    @AppStorage("notchifyQuickNotes") private var notesText: String = ""
    @State private var showSavedAlert = false
    @State private var isShelfTargeted = false
    @State private var isAirDropTargeted = false
    
    private var action1: QuickActionType {
        QuickActionType(rawValue: actionButton1Raw) ?? .capture
    }
    
    private var action2: QuickActionType {
        QuickActionType(rawValue: actionButton2Raw) ?? .lock
    }
    
    var body: some View {
        VStack(spacing: 5) {
            // Top Bar: Action Buttons (left) + Tab Selector (center) + Note Tools (right)
            HStack(spacing: 6) {
                // Action Buttons on left
                HStack(spacing: 4) {
                    QuickActionButtonView(actionType: action1, viewModel: viewModel)
                    QuickActionButtonView(actionType: action2, viewModel: viewModel)
                }
                .frame(width: 140)
                
                // Tabs in center
                HStack(spacing: 3) {
                    Button(action: { selectedTab = "files" }) {
                        HStack(spacing: 3) {
                            Image(systemName: "tray.fill")
                                .font(.system(size: 8))
                            Text(fileManager.files.isEmpty ? "Shelf" : "Shelf (\(fileManager.files.count))")
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(isShelfTargeted ? Color.white.opacity(0.15) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .onDrop(of: [.fileURL], isTargeted: $isShelfTargeted) { providers in
                        selectedTab = "files"
                        fileManager.loadAndAddFiles(from: providers)
                        return true
                    }
                    
                    Button(action: { selectedTab = "airdrop" }) {
                        HStack(spacing: 3) {
                            Image(systemName: "airplayaudio")
                                .font(.system(size: 8))
                            Text("AirDrop")
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(isAirDropTargeted ? Color.blue.opacity(0.3) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .onDrop(of: [.fileURL], isTargeted: $isAirDropTargeted) { providers in
                        selectedTab = "airdrop"
                        fileManager.sendAirDrop(from: providers)
                        return true
                    }
                    
                    Button(action: { selectedTab = "notes" }) {
                        HStack(spacing: 3) {
                            Image(systemName: "note.text")
                                .font(.system(size: 8))
                            Text("Notes")
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // Right Tools: Save to Notes, Copy, Clear
                HStack(spacing: 4) {
                    if showSavedAlert {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8.5))
                                .foregroundColor(.green)
                            Text("Saved to Notes!")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(.green)
                        }
                        .transition(.opacity)
                    } else {
                        Button(action: saveToNotesApp) {
                            HStack(spacing: 2) {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 8))
                                Text("Save to Notes")
                                    .font(.system(size: 8.5, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: copyToClipboard) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 8.5))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(4)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("Copy notes")
                    
                    if !notesText.isEmpty {
                        Button(action: { notesText = "" }) {
                            Image(systemName: "trash")
                                .font(.system(size: 8.5))
                                .foregroundColor(.white.opacity(0.45))
                                .padding(4)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .help("Clear notes")
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            
            // Full-width Text Editor
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
                
                if notesText.isEmpty {
                    Text("Type quick notes, ideas, todo lists... (Auto-saved continuously)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.28))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                }
                
                TextEditor(text: $notesText)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.92))
                    .scrollContentBackground(.hidden)
                    .padding(4)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06))
        .cornerRadius(13)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func saveToNotesApp() {
        QuickNotesManager.shared.exportToAppleNotes(text: notesText) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                showSavedAlert = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSavedAlert = false
                }
            }
        }
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(notesText, forType: .string)
    }
}

// MARK: - File Shelf Manager

class FileShelfManager: ObservableObject {
    static let shared = FileShelfManager()
    
    @Published var files: [URL] = []
    
    func addFile(url: URL) {
        let standardized = url.standardizedFileURL
        if !files.contains(where: { $0.standardizedFileURL == standardized }) {
            files.append(standardized)
        }
    }

    func addFiles(_ newURLs: [URL]) {
        for url in newURLs {
            let standardized = url.standardizedFileURL
            if !files.contains(where: { $0.standardizedFileURL == standardized }) {
                files.append(standardized)
            }
        }
    }
    
    func removeFile(url: URL) {
        let standardized = url.standardizedFileURL
        files.removeAll(where: { $0.standardizedFileURL == standardized })
    }
    
    func clearAll() {
        files.removeAll()
    }
    
    func airDropFile(url: URL) {
        let service = NSSharingService(named: .sendViaAirDrop)
        service?.perform(withItems: [url])
    }

    func extractURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        var collectedURLs: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            collectedURLs.append(url)
                        }
                    }
                    group.leave()
                }
            } else {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    var resolved: URL?
                    if let url = item as? URL {
                        resolved = url
                    } else if let url = item as? NSURL {
                        resolved = url as URL
                    } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        resolved = url
                    } else if let data = item as? Data, let str = String(data: data, encoding: .utf8), let url = URL(string: str) {
                        resolved = url
                    }
                    if let resolved = resolved {
                        DispatchQueue.main.async {
                            collectedURLs.append(resolved)
                        }
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            completion(collectedURLs)
        }
    }

    func loadAndAddFiles(from providers: [NSItemProvider]) {
        extractURLs(from: providers) { [weak self] urls in
            guard !urls.isEmpty else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                self?.addFiles(urls)
            }
        }
    }

    func sendAirDrop(from providers: [NSItemProvider]) {
        extractURLs(from: providers) { urls in
            guard !urls.isEmpty else { return }
            let service = NSSharingService(named: .sendViaAirDrop)
            service?.perform(withItems: urls)
        }
    }
}

// MARK: - Storage & AirDrop Column (Left)

struct StorageShelfColumnView: View {
    var viewModel: NotchViewModel? = nil
    @ObservedObject var manager = FileShelfManager.shared
    @AppStorage("storageSelectedTab") private var selectedTab: String = "files"
    @AppStorage("quickActionButton1") private var actionButton1Raw: String = QuickActionType.capture.rawValue
    @AppStorage("quickActionButton2") private var actionButton2Raw: String = QuickActionType.lock.rawValue
    @State private var isShelfTargeted = false
    @State private var isAirDropTargeted = false
    
    private var action1: QuickActionType {
        QuickActionType(rawValue: actionButton1Raw) ?? .capture
    }
    
    private var action2: QuickActionType {
        QuickActionType(rawValue: actionButton2Raw) ?? .lock
    }
    
    private var isAirDropMode: Bool {
        selectedTab == "airdrop"
    }
    
    var body: some View {
        VStack(spacing: 5) {
            // Top Action Buttons: Customizable Quick Action Buttons
            HStack(spacing: 5) {
                QuickActionButtonView(actionType: action1, viewModel: viewModel)
                QuickActionButtonView(actionType: action2, viewModel: viewModel)
            }
            .padding(.horizontal, 5)
            .padding(.top, 5)

            // Storage Section (Below the buttons)
            VStack(spacing: 4) {
                // Tab Selector Header
                HStack(spacing: 3) {
                    // Shelf tab
                    Button(action: { selectedTab = "files" }) {
                        HStack(spacing: 3) {
                            Image(systemName: "tray.fill")
                                .font(.system(size: 8))
                            Text(manager.files.isEmpty ? "Shelf" : "Shelf (\(manager.files.count))")
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(selectedTab == "files" ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(selectedTab == "files" ? Color.white.opacity(0.2) : (isShelfTargeted ? Color.white.opacity(0.12) : Color.clear))
                        )
                    }
                    .buttonStyle(.plain)
                    .onDrop(of: [.fileURL], isTargeted: $isShelfTargeted) { providers in
                        selectedTab = "files"
                        manager.loadAndAddFiles(from: providers)
                        return true
                    }

                    // AirDrop tab
                    Button(action: { selectedTab = "airdrop" }) {
                        HStack(spacing: 3) {
                            Image(systemName: "airplayaudio")
                                .font(.system(size: 8))
                            Text("AirDrop")
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(selectedTab == "airdrop" ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(selectedTab == "airdrop" ? Color.white.opacity(0.2) : (isAirDropTargeted ? Color.blue.opacity(0.3) : Color.clear))
                        )
                    }
                    .buttonStyle(.plain)
                    .onDrop(of: [.fileURL], isTargeted: $isAirDropTargeted) { providers in
                        selectedTab = "airdrop"
                        manager.sendAirDrop(from: providers)
                        return true
                    }

                    // Notes tab
                    Button(action: { selectedTab = "notes" }) {
                        HStack(spacing: 3) {
                            Image(systemName: "note.text")
                                .font(.system(size: 8))
                            Text("Notes")
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(selectedTab == "notes" ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(selectedTab == "notes" ? Color.white.opacity(0.2) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if selectedTab == "files" && !manager.files.isEmpty {
                        Button(action: { manager.clearAll() }) {
                            Text("Clear")
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)

                // Storage Content Area
                if isAirDropMode {
                    // AirDrop Instant Send Zone
                    VStack(spacing: 3) {
                        Image(systemName: "airplayaudio")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(isAirDropTargeted ? .blue : .white.opacity(0.75))

                        Text(isAirDropTargeted ? "Release to AirDrop!" : "Drop files to AirDrop")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(isAirDropTargeted ? Color.blue.opacity(0.18) : Color.white.opacity(0.04))
                    .cornerRadius(10)
                    .padding(.horizontal, 5)
                    .padding(.bottom, 5)
                    .onDrop(of: [.fileURL], isTargeted: $isAirDropTargeted) { providers in
                        manager.sendAirDrop(from: providers)
                        return true
                    }
                    .onTapGesture {
                        triggerAirDropPicker()
                    }
                } else {
                    // File Shelf Zone
                    if !manager.files.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(manager.files, id: \.self) { fileURL in
                                    CompactFileItemView(url: fileURL, onRemove: {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            manager.removeFile(url: fileURL)
                                        }
                                    })
                                }

                                // Quick drop target tile at end of shelf
                                VStack(spacing: 2) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(isShelfTargeted ? .white : .white.opacity(0.35))
                                    Text("Drop")
                                        .font(.system(size: 7.5, weight: .medium))
                                        .foregroundColor(isShelfTargeted ? .white : .white.opacity(0.35))
                                }
                                .frame(width: 38, height: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isShelfTargeted ? Color.white.opacity(0.18) : Color.white.opacity(0.03))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            isShelfTargeted ? Color.white.opacity(0.6) : Color.white.opacity(0.1),
                                            style: StrokeStyle(lineWidth: 1, dash: [3])
                                        )
                                )
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(isShelfTargeted ? Color.white.opacity(0.06) : Color.clear)
                        .cornerRadius(10)
                        .padding(.horizontal, 5)
                        .padding(.bottom, 5)
                        .onDrop(of: [.fileURL], isTargeted: $isShelfTargeted) { providers in
                            manager.loadAndAddFiles(from: providers)
                            return true
                        }
                    } else {
                        VStack(spacing: 3) {
                            Image(systemName: "tray.and.arrow.down")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(isShelfTargeted ? .white : .white.opacity(0.45))
                                .offset(y: isShelfTargeted ? -2 : 0)
                                .animation(.easeInOut(duration: 0.2), value: isShelfTargeted)

                            Text(isShelfTargeted ? "Release to hold!" : "Drop files to hold")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(isShelfTargeted ? .white : .white.opacity(0.55))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(isShelfTargeted ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                        .cornerRadius(10)
                        .padding(.horizontal, 5)
                        .padding(.bottom, 5)
                        .onDrop(of: [.fileURL], isTargeted: $isShelfTargeted) { providers in
                            manager.loadAndAddFiles(from: providers)
                            return true
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06))
        .cornerRadius(13)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func triggerAirDropPicker() {
        if !manager.files.isEmpty {
            let service = NSSharingService(named: .sendViaAirDrop)
            service?.perform(withItems: manager.files)
        } else {
            let panel = NSOpenPanel()
            panel.title = "Select Files to AirDrop"
            panel.prompt = "AirDrop"
            panel.allowsMultipleSelection = true
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.begin { response in
                if response == .OK && !panel.urls.isEmpty {
                    let service = NSSharingService(named: .sendViaAirDrop)
                    service?.perform(withItems: panel.urls)
                }
            }
        }
    }
}

// MARK: - Compact File Item View with Rich Thumbnail Preview

struct CompactFileItemView: View {
    let url: URL
    let onRemove: () -> Void
    
    @StateObject private var loader: FileThumbnailLoader
    @State private var isHovered = false
    
    init(url: URL, onRemove: @escaping () -> Void) {
        self.url = url
        self.onRemove = onRemove
        _loader = StateObject(wrappedValue: FileThumbnailLoader(url: url))
    }
    
    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                // High-resolution preview / thumbnail
                Group {
                    if let thumb = loader.thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.08))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.white.opacity(isHovered ? 0.3 : 0.08), lineWidth: 1)
                )
                .clipped()
                
                // Hover Remove Button
                if isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.black.opacity(0.75)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                }
            }
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
            
            // Filename
            Text(url.lastPathComponent)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(isHovered ? .white : .white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 44)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(isHovered ? 0.12 : 0.02))
        )
        .onHover { hover in
            isHovered = hover
            if hover { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(url)
        }
        .onDrag {
            NSItemProvider(object: url as NSURL)
        }
    }
}

// MARK: - Media & Camera Mirror Column (Right)

struct MediaCameraColumnView: View {
    @ObservedObject var musicManager: MusicManager
    @Binding var cameraEnabled: Bool
    let onOpenMusicSource: () -> Void
    @ObservedObject var cameraManager = CameraManager.shared
    
    private var primaryLineText: String {
        let title = musicManager.playbackState.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Not Playing" : title
    }

    private var secondaryLineText: String {
        let artist = musicManager.playbackState.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return artist.isEmpty ? "Music" : artist
    }

    var body: some View {
        VStack(spacing: 5) {
            // Mini Audio / Music Strip (Always present so camera size is consistent whether music is playing or not)
            HStack(spacing: 6) {
                Button(action: onOpenMusicSource) {
                    Group {
                        if let image = musicManager.albumArt {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: musicManager.isVisible ? musicManager.fallbackSymbolName : "music.note")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(musicManager.isVisible ? primaryLineText : "Not Playing")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(musicManager.isVisible && !secondaryLineText.isEmpty ? secondaryLineText : "Music")
                        .font(.system(size: 8.5))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Button(action: {
                    musicManager.togglePlayPause()
                }) {
                    Image(systemName: musicManager.playbackState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .cornerRadius(8)
            
            // Prominent Camera Mirror (Flipped horizontally like a real mirror)
            ZStack {
                if cameraEnabled {
                    if let cgImage = cameraManager.frame {
                        Image(cgImage, scale: 1.0, orientation: .up, label: Text("Mirror"))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .scaleEffect(x: -1, y: 1) // TRUE HORIZONTAL MIRROR FLIP!
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                            .clipped()
                    } else {
                        ZStack {
                            Color.black.opacity(0.4)
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    }
                    
                    // Live mirror overlay controls
                    VStack {
                        HStack {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 5, height: 5)
                                Text("Live Mirror")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Capsule())
                            
                            Spacer()
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    cameraEnabled = false
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.85))
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(5)
                        
                        Spacer()
                    }
                } else {
                    // Camera Off Setting / Viewfinder Tile
                    VStack(spacing: 5) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.45))
                        
                        Text("Camera Mirror")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                cameraEnabled = true
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "power")
                                    .font(.system(size: 8, weight: .bold))
                                Text("Turn On")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(Color.white.opacity(0.95))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)
            .clipped()
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06))
        .cornerRadius(13)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            if cameraEnabled {
                cameraManager.start()
            }
        }
        .onChange(of: cameraEnabled) { _, isEnabled in
            if isEnabled {
                cameraManager.start()
            } else {
                cameraManager.stop()
            }
        }
        .onDisappear {
            cameraManager.stop()
        }
    }
}
