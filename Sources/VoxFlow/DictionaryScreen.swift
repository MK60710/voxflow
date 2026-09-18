import SwiftUI
import VoxFlowCore

/// Step 4 (plans/voxflow-windowed-ui.md): the old SettingsView's
/// "Dictionary" section, ported verbatim in behavior into its own sidebar
/// screen. Does NOT touch or delete the old SettingsView — that stays
/// intact until Step 6.
struct DictionaryScreen: View {
    @ObservedObject private var dictionary = DictionaryCoordinator.shared
    @State private var newTerm = ""
    @State private var newSoundsLike = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dictionary")
                .font(VoxFlowTheme.heading())
                .foregroundStyle(VoxFlowTheme.primaryText)

            Text("Add names or jargon VoxFlow should spell correctly (e.g. \"CogniSwitch\"). \"Sounds like\" is optional — use it when the correct spelling doesn't sound the way it's spelled.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let loadError = dictionary.loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if dictionary.entries.isEmpty {
                Text("No dictionary entries yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(dictionary.entries) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.term)
                            if let soundsLike = entry.soundsLike, !soundsLike.isEmpty {
                                Text("sounds like: \(soundsLike)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            dictionary.remove(id: entry.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .listStyle(.inset)
            }

            HStack {
                TextField("Term (e.g. CogniSwitch)", text: $newTerm)
                TextField("Sounds like (optional)", text: $newSoundsLike)
                Button("Add") {
                    dictionary.add(term: newTerm, soundsLike: newSoundsLike.isEmpty ? nil : newSoundsLike)
                    newTerm = ""
                    newSoundsLike = ""
                }
                .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VoxFlowTheme.contentBackground)
    }
}
