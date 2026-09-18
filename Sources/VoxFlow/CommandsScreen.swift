import SwiftUI
import VoxFlowCore

/// Step 3 (plans/voxflow-windowed-ui.md): the old SettingsView's
/// "Commands" section, ported verbatim in behavior into its own sidebar
/// screen. Does NOT touch or delete the old SettingsView — that stays
/// intact until Step 6.
struct CommandsScreen: View {
    @ObservedObject private var commandMode = CommandModeCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Commands")
                .font(VoxFlowTheme.heading())
                .foregroundStyle(VoxFlowTheme.primaryText)

            Toggle("Voice commands", isOn: $commandMode.commandModeEnabled)
            Text("Say a command phrase exactly and it executes instead of being typed — e.g. \"select all of the budget items\" still types as text.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(VoiceCommand.allCases, id: \.self) { command in
                HStack {
                    Text("\u{201C}\(command.phrase)\u{201D}")
                    Spacer()
                    Text(command.displayName)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VoxFlowTheme.contentBackground)
    }
}
