import AppKit
import SwiftUI
import VoxFlowCore

/// Step 5 (plans/voxflow-windowed-ui.md): `TranscriptLogCoordinator`'s
/// content, ported verbatim in behavior into the new window's sidebar —
/// replaces its old standalone `NSWindow`-hosted view (that
/// window-management code is removed from `TranscriptLogCoordinator`
/// itself as part of this step; the `@Published`/store logic there is
/// untouched).
struct TranscriptLogScreen: View {
    @ObservedObject private var log = TranscriptLogCoordinator.shared
    @State private var copiedEntryID: TranscriptLogEntry.ID?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transcript Log")
                    .font(VoxFlowTheme.heading())
                    .foregroundStyle(VoxFlowTheme.primaryText)
                Spacer()
                Button("Clear") {
                    log.clear()
                }
                .disabled(log.entries.isEmpty)
            }
            .padding(24)

            Text("Every dictation lands here too, permanently — copy from here if it didn't paste where you expected.")
                .font(.caption)
                .foregroundStyle(VoxFlowTheme.secondaryText)
                .padding(.horizontal, 24)

            if let loadError = log.loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
            }

            Divider()
                .padding(.top, 12)

            if log.entries.isEmpty {
                Spacer()
                Text("Nothing dictated yet.")
                    .foregroundStyle(VoxFlowTheme.secondaryText)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(log.entries) { entry in
                            entryRow(entry)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VoxFlowTheme.contentBackground)
    }

    @ViewBuilder
    private func entryRow(_ entry: TranscriptLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .font(.caption)
                    .foregroundStyle(VoxFlowTheme.secondaryText)
                Spacer()
                Button(copiedEntryID == entry.id ? "Copied" : "Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(entry.text, forType: .string)
                    copiedEntryID = entry.id
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            Text(entry.text)
                .foregroundStyle(VoxFlowTheme.primaryText)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(VoxFlowTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
