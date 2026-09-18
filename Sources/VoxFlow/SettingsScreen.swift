import SwiftUI
import VoxFlowCore

/// Step 3 (plans/voxflow-windowed-ui.md): General/Transcription/Cleanup
/// ported into the new window as one screen, per docs/window-ux-plan.md's
/// sign-off (these are infrastructure toggles, grouped together, unlike
/// the content-area screens which each get their own sidebar row).
/// Ported verbatim in behavior from the old `SettingsView`'s Form — same
/// controls, same bindings, new layout (full window width instead of a
/// fixed 460pt column). Deliberately does NOT touch or delete anything in
/// the old `SettingsView` — that stays intact until Step 6.
struct SettingsScreen: View {
    @ObservedObject private var transcription = TranscriptionCoordinator.shared
    @ObservedObject private var cleanup = CleanupCoordinator.shared
    @ObservedObject private var launchAtLogin = LaunchAtLoginCoordinator.shared
    @ObservedObject private var hotkey = HotkeyCoordinator.shared

    var body: some View {
        ScrollView {
            Text("Settings")
                .font(VoxFlowTheme.heading())
                .foregroundStyle(VoxFlowTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)

            Form {
                Section("General") {
                    Toggle("Launch at login", isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    ))
                    if let error = launchAtLogin.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Picker("Hotkey", selection: $hotkey.selectedHotkey) {
                        ForEach(HotkeyOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Text("Hold this key anywhere to dictate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Onboarding…") {
                        OnboardingCoordinator.shared.show()
                    }
                }

                Section("Transcription") {
                    Toggle("Prefer local (offline) speech engine", isOn: $transcription.preferLocalEngine)
                    Text("Off (default): tries Groq (cloud) first, falls back to Apple's on-device speech engine if Groq fails or has no key. On: tries the on-device engine first — fully offline, but generally slower and possibly less accurate than Groq.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let engineName = transcription.lastTranscriptionEngineName {
                        Text("Last dictation transcribed via: \(engineName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Cleanup") {
                    Toggle("Clean up dictated text", isOn: $cleanup.cleanupEnabled)
                    Text("Removes filler words and fixes punctuation before inserting text. Hold Shift while releasing the hotkey to insert the raw transcript for one dictation, regardless of this setting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Auto-edits (\"scratch that\")", isOn: $cleanup.autoEditsEnabled)
                        .disabled(!cleanup.cleanupEnabled)
                    Text("Honors spoken corrections within one dictation — \"send it Monday, scratch that, Tuesday\" becomes \"Send it Tuesday.\" Only applies while cleanup above is on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Format step-by-step dictation as a list", isOn: $cleanup.listFormattingEnabled)
                        .disabled(!cleanup.cleanupEnabled)
                    Text("Phrases like \"first upload the document, next break it down, then organize a draft\" become a numbered list, one step per line. Doesn't apply in Code/Terminal apps. Only applies while cleanup above is on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let source = cleanup.lastCleanupSource {
                        Text(lastCleanupSourceLabel(source))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(24)
        }
        .background(VoxFlowTheme.contentBackground)
    }

    private func lastCleanupSourceLabel(_ source: CleanupSource) -> String {
        switch source {
        case .cleaned(let engineName):
            return "Last cleanup: \(engineName)"
        case .raw(let reason):
            return "Last dictation used raw text: \(reason)"
        }
    }
}
