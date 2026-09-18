import Foundation

/// Pure logic for splitting a String into UTF-16-unit chunks small enough
/// for a single CGEvent's `keyboardSetUnicodeString` call (blueprint Step 4,
/// task 2). The reference survey (docs/reference-report.md) found that API
/// only reliably carries ~20 UTF-16 units per event, so longer strings need
/// chunking. Never splits a surrogate pair (an astral-plane character like
/// an emoji is TWO UTF-16 units that must stay in the same chunk — CGEvent
/// would otherwise post a lone, unpaired surrogate and the receiving app
/// would show mojibake or drop the character silently).
///
/// Kept AppKit/CGEvent-free (see AudioBufferConversion.swift for the same
/// module-boundary convention) so it's testable without a live event tap —
/// `Sources/VoxFlow/CGEventUnicodeInserter.swift` is the only caller.
public enum UTF16Chunker {
    /// Default per-event ceiling; matches the blueprint's "~20 UTF-16 units
    /// per event" note for `keyboardSetUnicodeString`.
    public static let defaultMaxUnitsPerChunk = 20

    /// Splits `text`'s UTF-16 representation into chunks of at most
    /// `maxUnitsPerChunk` code units each, without ever separating a
    /// surrogate pair across two chunks. Returns raw UTF-16 code units
    /// (`[[UInt16]]`) — the exact shape `CGEvent.keyboardSetUnicodeString`
    /// wants (`UniChar` is a `UInt16` typealias). Returns `[]` for an empty
    /// string.
    ///
    /// If a single surrogate pair is wider than `maxUnitsPerChunk` itself
    /// (only possible if the caller passes `maxUnitsPerChunk < 2`), the pair
    /// is still kept together as its own oversized chunk rather than split —
    /// correctness of the character wins over the size ceiling.
    public static func chunks(for text: String, maxUnitsPerChunk: Int = defaultMaxUnitsPerChunk) -> [[UInt16]] {
        precondition(maxUnitsPerChunk > 0, "maxUnitsPerChunk must be positive")
        let units = Array(text.utf16)
        guard !units.isEmpty else { return [] }

        var result: [[UInt16]] = []
        var current: [UInt16] = []
        current.reserveCapacity(maxUnitsPerChunk)

        var index = 0
        while index < units.count {
            let unit = units[index]
            let isHighSurrogate = (0xD800...0xDBFF).contains(unit)
            let formsPair = isHighSurrogate
                && index + 1 < units.count
                && (0xDC00...0xDFFF).contains(units[index + 1])
            let unitWidth = formsPair ? 2 : 1

            if !current.isEmpty, current.count + unitWidth > maxUnitsPerChunk {
                result.append(current)
                current = []
                current.reserveCapacity(maxUnitsPerChunk)
            }

            current.append(unit)
            if formsPair {
                current.append(units[index + 1])
            }
            index += unitWidth
        }

        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}
