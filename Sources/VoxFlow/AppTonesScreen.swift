import SwiftUI
import VoxFlowCore

/// Step 3 (plans/voxflow-windowed-ui.md): the old SettingsView's
/// `ContextToneSettingsSection`, ported verbatim in behavior into its own
/// sidebar screen — this was the feature the plan's own first draft
/// missed entirely (per the adversarial review), so it gets extra care
/// here to make sure every control from the original carried over. Does
/// NOT touch or delete the old SettingsView/ContextToneSettingsSection —
/// those stay intact until Step 6.
struct AppTonesScreen: View {
    @ObservedObject private var store = ContextSettingsStore.shared
    @State private var runningAppOptions: [ContextSettingsStore.RunningAppOption] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App Tones")
                .font(VoxFlowTheme.heading())
                .foregroundStyle(VoxFlowTheme.primaryText)

            Text("VoxFlow adapts cleanup tone to the app you're dictating into — casual for messaging, professional for email/docs, minimal for code and terminals. Assignments below override the built-in defaults.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(sortedAssignments, id: \.bundleIdentifier) { entry in
                    HStack {
                        Text(entry.bundleIdentifier)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Picker("", selection: toneBinding(for: entry.bundleIdentifier)) {
                            ForEach(ToneProfile.allCases, id: \.self) { tone in
                                Text(tone.displayName).tag(tone)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                        Button {
                            store.removeAssignment(forBundleIdentifier: entry.bundleIdentifier)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this assignment")
                    }
                }
            }
            .listStyle(.inset)

            HStack {
                Menu("Add running app…") {
                    if runningAppOptions.isEmpty {
                        Text("No running apps found")
                    } else {
                        ForEach(runningAppOptions) { option in
                            Button(option.displayName) {
                                store.setTone(.neutral, forBundleIdentifier: option.bundleIdentifier)
                            }
                        }
                    }
                }
                .onAppear {
                    runningAppOptions = store.runningApplicationOptions()
                }
                .onTapGesture {
                    runningAppOptions = store.runningApplicationOptions()
                }

                Spacer()

                Button("Reset to Defaults") {
                    store.resetToDefaults()
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VoxFlowTheme.contentBackground)
    }

    private var sortedAssignments: [(bundleIdentifier: String, tone: ToneProfile)] {
        store.assignments
            .map { (bundleIdentifier: $0.key, tone: $0.value) }
            .sorted { $0.bundleIdentifier < $1.bundleIdentifier }
    }

    private func toneBinding(for bundleIdentifier: String) -> Binding<ToneProfile> {
        Binding(
            get: { store.assignments[bundleIdentifier] ?? .neutral },
            set: { store.setTone($0, forBundleIdentifier: bundleIdentifier) }
        )
    }
}
