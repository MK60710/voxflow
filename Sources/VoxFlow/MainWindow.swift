import SwiftUI
import VoxFlowCore

/// The window's sidebar screen list — approved in `docs/window-ux-plan.md`
/// (Step 1, signed off 2026-08-22). Settings groups General/Transcription/
/// Cleanup as sub-sections (technical/infrastructure toggles) rather than
/// giving each its own sidebar row, keeping the sidebar focused on content
/// areas (Insights, Dictionary, Snippets, App Tones) the way Wispr Flow's
/// own sidebar does.
enum MainWindowScreen: String, CaseIterable, Identifiable {
    case dictation
    case insights
    case transcriptLog
    case dictionary
    case snippets
    case appTones
    case commands
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation: return "Dictation"
        case .insights: return "Insights"
        case .transcriptLog: return "Transcript Log"
        case .dictionary: return "Dictionary"
        case .snippets: return "Snippets"
        case .appTones: return "App Tones"
        case .commands: return "Commands"
        case .settings: return "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .dictation: return "waveform"
        case .insights: return "chart.bar"
        case .transcriptLog: return "text.alignleft"
        case .dictionary: return "character.book.closed"
        case .snippets: return "text.badge.plus"
        case .appTones: return "theatermasks"
        case .commands: return "command"
        case .settings: return "gearshape"
        }
    }
}

/// Step 5 (plans/voxflow-windowed-ui.md): shared selection state so a
/// call site outside the window (e.g. `MenuContent`'s "Insights…"/
/// "Transcript Log…" buttons, still pointing at their old standalone
/// windows until Step 6 removes them) can navigate the shared window to a
/// specific screen before opening it, instead of each screen needing its
/// own way in.
@MainActor
final class MainWindowNavigator: ObservableObject {
    static let shared = MainWindowNavigator()
    @Published var selection: MainWindowScreen = .dictation
    private init() {}
}

/// Step 2b (plans/voxflow-windowed-ui.md): the real navigation shell,
/// replacing Step 2a's placeholder spike content now that the window's
/// open/close/reopen lifecycle is confirmed correct. Home (Dictation) is
/// built for real here; every other screen is a placeholder until S3/S4/S5
/// fill them in — each of those steps only adds a `case` render below plus
/// its own new screen file, per the plan's parallel-safe design.
struct MainWindowContent: View {
    @ObservedObject private var navigator = MainWindowNavigator.shared

    private var selection: Binding<MainWindowScreen?> {
        Binding(
            get: { navigator.selection },
            set: { navigator.selection = $0 ?? .dictation }
        )
    }

    var body: some View {
        NavigationSplitView {
            // Step 7 (plans/voxflow-windowed-ui.md, "Direction D"): a plain
            // List's native selection highlight is a system blue/gray that
            // can't be reliably restyled on macOS — built as custom row
            // buttons instead so the pill-shaped selected state matches the
            // approved mockup exactly, in both appearances.
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(MainWindowScreen.allCases) { screen in
                        sidebarRow(screen)
                    }
                }
                .padding(10)
            }
            .background(VoxFlowTheme.sidebarBackground)
            // Wide enough that "Transcript Log" never truncates (a real
            // cosmetic bug flagged after Step 2b's live screenshot).
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .navigationTitle("VoxFlow")
            // Re-homed from the old dropdown's ⌘, / ⌘L shortcuts (review
            // flagged these as silently lost otherwise) — hidden buttons
            // so the shortcut works whenever this window is key, without
            // a second visible affordance next to the sidebar rows above.
            .background {
                Button("") { navigator.selection = .settings }
                    .keyboardShortcut(",", modifiers: .command)
                    .hidden()
                Button("") { navigator.selection = .transcriptLog }
                    .keyboardShortcut("l", modifiers: .command)
                    .hidden()
            }
        } detail: {
            switch navigator.selection {
            case .dictation:
                DictationHomeScreen()
            case .insights:
                InsightsScreen()
            case .transcriptLog:
                TranscriptLogScreen()
            case .dictionary:
                DictionaryScreen()
            case .snippets:
                SnippetsScreen()
            case .appTones:
                AppTonesScreen()
            case .commands:
                CommandsScreen()
            case .settings:
                SettingsScreen()
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    @ViewBuilder
    private func sidebarRow(_ screen: MainWindowScreen) -> some View {
        let isActive = navigator.selection == screen
        Button {
            navigator.selection = screen
        } label: {
            HStack(spacing: 10) {
                Image(systemName: screen.symbolName)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? VoxFlowTheme.accent : VoxFlowTheme.secondaryText)
                    .frame(width: 18)
                Text(screen.title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? VoxFlowTheme.primaryText : VoxFlowTheme.secondaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isActive ? VoxFlowTheme.selectedBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Real content — same data `MenuContent`'s `statusLine`/`engineSection`/
/// `cleanupSection` already read, laid out fresh for a full-size screen
/// instead of a dropdown. Deliberately duplicates the read-only display
/// logic rather than sharing `MenuContent`'s private view code: the two
/// surfaces will keep diverging in layout as later steps land (this one
/// grows, the dropdown shrinks in Step 6), and there's currently no third
/// consumer that would justify extracting a shared component yet.
struct DictationHomeScreen: View {
    @ObservedObject private var coordinator = DictationCoordinator.shared
    @ObservedObject private var transcription = TranscriptionCoordinator.shared
    @ObservedObject private var cleanup = CleanupCoordinator.shared
    @ObservedObject private var hotkey = HotkeyCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Dictation")
                .font(VoxFlowTheme.heading())
                .foregroundStyle(VoxFlowTheme.primaryText)

            statusLine

            card("Engine") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(transcription.engineStatus.menuLabel)
                        .foregroundStyle(transcription.engineStatus.isHealthy ? VoxFlowTheme.primaryText : Color.orange)
                    if let engineName = transcription.lastTranscriptionEngineName {
                        let expectedPrefix = transcription.preferLocalEngine ? "apple-speech:" : "groq:"
                        let isOnFallback = !engineName.hasPrefix(expectedPrefix)
                        Text("Transcribed via: \(engineName)")
                            .font(.caption)
                            .foregroundStyle(isOnFallback ? Color.orange : VoxFlowTheme.secondaryText)
                    }
                }
            }

            card("Cleanup") {
                VStack(alignment: .leading, spacing: 6) {
                    if let source = cleanup.lastCleanupSource {
                        switch source {
                        case .cleaned(let engineName):
                            Text("Cleanup: \(engineName)")
                                .foregroundStyle(VoxFlowTheme.primaryText)
                        case .raw(let reason):
                            Text("Cleanup: raw — \(reason)")
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Text("No dictation yet this session.")
                            .foregroundStyle(VoxFlowTheme.secondaryText)
                    }
                    if let tone = cleanup.lastToneUsed {
                        Text("Tone: \(tone.displayName)")
                            .font(.caption)
                            .foregroundStyle(VoxFlowTheme.secondaryText)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VoxFlowTheme.contentBackground)
    }

    /// The mockup's soft filled rounded card — an accent-tinted label above
    /// freeform content, replacing `GroupBox`'s plain native chrome.
    @ViewBuilder
    private func card<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(VoxFlowTheme.accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(VoxFlowTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: VoxFlowTheme.cardCornerRadius))
    }

    @ViewBuilder
    private var statusLine: some View {
        switch coordinator.indicatorState {
        case .idle:
            if let duration = coordinator.lastRecordingDuration {
                Text(String(format: "Last recording: %.1fs", duration))
                    .foregroundStyle(VoxFlowTheme.secondaryText)
            } else {
                Text("Hold \(hotkey.selectedHotkey.displayName) anywhere to dictate")
                    .foregroundStyle(VoxFlowTheme.secondaryText)
            }
        case .recording:
            Text("Recording…")
                .foregroundStyle(.red)
        case .toggleRecording:
            Text("Recording — tap \(hotkey.selectedHotkey.displayName) to stop")
                .foregroundStyle(.red)
        case .transcribing:
            Text("Transcribing…")
                .foregroundStyle(VoxFlowTheme.secondaryText)
        case .secureInputBlocked:
            Text("Blocked by secure input")
                .foregroundStyle(.orange)
        case .permissionNeeded:
            Text("Needs Accessibility permission")
                .foregroundStyle(.orange)
        case .aborted(let reason):
            Text(reason)
                .foregroundStyle(.orange)
        }
    }
}
