import Testing
@testable import VoxFlowCore

@Suite("UTF16Chunker")
struct UTF16ChunkerTests {

    // MARK: - Basic chunking

    @Test("empty string produces no chunks")
    func emptyStringProducesNoChunks() {
        #expect(UTF16Chunker.chunks(for: "", maxUnitsPerChunk: 20).isEmpty)
    }

    @Test("a string shorter than the max fits in a single chunk")
    func shortStringFitsInOneChunk() {
        let text = "café"
        let chunks = UTF16Chunker.chunks(for: text, maxUnitsPerChunk: 20)
        #expect(chunks.count == 1)
        #expect(chunks[0] == Array(text.utf16))
    }

    @Test("a string exactly at the max boundary fits in a single chunk")
    func exactBoundaryFitsInOneChunk() {
        let text = String(repeating: "a", count: 20)
        let chunks = UTF16Chunker.chunks(for: text, maxUnitsPerChunk: 20)
        #expect(chunks.count == 1)
        #expect(chunks[0].count == 20)
    }

    @Test("a string one unit over the max splits into two chunks")
    func oneUnitOverMaxSplitsIntoTwoChunks() {
        let text = String(repeating: "a", count: 21)
        let chunks = UTF16Chunker.chunks(for: text, maxUnitsPerChunk: 20)
        #expect(chunks.count == 2)
        #expect(chunks[0].count == 20)
        #expect(chunks[1].count == 1)
    }

    @Test("concatenating all chunks reconstructs the original UTF-16 units, lossless")
    func chunksReconstructOriginalUnits() {
        let text = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 5)
        let chunks = UTF16Chunker.chunks(for: text, maxUnitsPerChunk: 20)
        let reconstructed = chunks.flatMap { $0 }
        #expect(reconstructed == Array(text.utf16))
    }

    @Test("no chunk exceeds the requested max size when no surrogate pair forces an exception")
    func noChunkExceedsMaxSize() {
        let text = String(repeating: "xyz ", count: 30)
        let chunks = UTF16Chunker.chunks(for: text, maxUnitsPerChunk: 20)
        for chunk in chunks {
            #expect(chunk.count <= 20)
        }
    }

    // MARK: - Surrogate-pair safety

    @Test("a surrogate-pair emoji is never split across two chunks, even sitting on the boundary")
    func surrogatePairNeverSplitAtBoundary() {
        // 19 ASCII units + a surrogate-pair emoji (2 units) = 21 total.
        // With maxUnitsPerChunk 20, the emoji's high surrogate would land
        // exactly on the boundary if the chunker split naively at 20 units.
        let emoji = "😀" // U+1F600 — a surrogate pair in UTF-16
        #expect(emoji.utf16.count == 2)
        let text = String(repeating: "a", count: 19) + emoji
        #expect(text.utf16.count == 21)

        let chunks = UTF16Chunker.chunks(for: text, maxUnitsPerChunk: 20)

        // The emoji's two units must both be present, together, in the same
        // chunk — never a lone high or low surrogate at a chunk edge.
        for chunk in chunks {
            var index = 0
            while index < chunk.count {
                let unit = chunk[index]
                let isHighSurrogate = (0xD800...0xDBFF).contains(unit)
                if isHighSurrogate {
                    #expect(index + 1 < chunk.count, "high surrogate must not be the last unit in its chunk")
                    if index + 1 < chunk.count {
                        #expect((0xDC00...0xDFFF).contains(chunk[index + 1]), "high surrogate must be followed by its low surrogate in the same chunk")
                    }
                    index += 2
                } else {
                    #expect(!(0xDC00...0xDFFF).contains(unit), "lone low surrogate found — a pair was split")
                    index += 1
                }
            }
        }

        // Still lossless overall.
        #expect(chunks.flatMap { $0 } == Array(text.utf16))
    }

    @Test("a string of many surrogate-pair emoji chunks correctly and losslessly")
    func manyEmojiChunkCorrectly() {
        let text = String(repeating: "😀", count: 15) // 30 UTF-16 units
        let chunks = UTF16Chunker.chunks(for: text, maxUnitsPerChunk: 20)
        #expect(chunks.flatMap { $0 } == Array(text.utf16))
        for chunk in chunks {
            #expect(chunk.count % 2 == 0, "every chunk should contain only whole surrogate pairs here")
        }
    }

    @Test("a maxUnitsPerChunk of 1 still keeps a surrogate pair together as one oversized chunk")
    func tinyMaxStillKeepsPairTogether() {
        let text = "😀"
        let chunks = UTF16Chunker.chunks(for: text, maxUnitsPerChunk: 1)
        #expect(chunks.count == 1)
        #expect(chunks[0].count == 2)
    }

    @Test("the blueprint's own test-harness string chunks losslessly at the default size")
    func testHarnessStringChunksLosslessly() {
        let text = "café ☕️ naïve"
        let chunks = UTF16Chunker.chunks(for: text, maxUnitsPerChunk: UTF16Chunker.defaultMaxUnitsPerChunk)
        #expect(chunks.flatMap { $0 } == Array(text.utf16))
    }
}
