import SwiftUI
import VoxFlowCore

/// Step 4 (plans/voxflow-windowed-ui.md): the old SettingsView's
/// "Snippets" section, ported verbatim in behavior into its own sidebar
/// screen. Does NOT touch or delete the old SettingsView — that stays
/// intact until Step 6.
struct SnippetsScreen: View {
    @ObservedObject private var snippets = SnippetCoordinator.shared
    @State private var newSnippetTrigger = ""
    @State private var newSnippetExpansion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Snippets")
                .font(VoxFlowTheme.heading())
                .foregroundStyle(VoxFlowTheme.primaryText)

            Text("Say a trigger phrase exactly and its saved text gets typed instead — e.g. \"my LinkedIn\" → your profile URL. Embedded mid-sentence, the trigger phrase still types as normal words.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let loadError = snippets.loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if snippets.entries.isEmpty {
                Text("No snippets yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(snippets.entries) { entry in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading) {
                            Text("\u{201C}\(entry.trigger)\u{201D}")
                            Text(entry.expansion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            snippets.remove(id: entry.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .listStyle(.inset)
            }

            VStack(alignment: .leading) {
                TextField("Trigger phrase (e.g. my LinkedIn)", text: $newSnippetTrigger)
                TextEditor(text: $newSnippetExpansion)
                    .frame(height: 60)
                    .overlay(alignment: .topLeading) {
                        if newSnippetExpansion.isEmpty {
                            Text("Text to insert")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                Button("Add Snippet") {
                    snippets.add(trigger: newSnippetTrigger, expansion: newSnippetExpansion)
                    newSnippetTrigger = ""
                    newSnippetExpansion = ""
                }
                .disabled(
                    newSnippetTrigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    newSnippetExpansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VoxFlowTheme.contentBackground)
    }
}
