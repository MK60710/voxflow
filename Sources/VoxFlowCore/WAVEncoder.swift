import Foundation

/// Pure PCM16 mono WAV byte encoder — no AVFoundation dependency, so it's
/// usable both by `VoxFlowCoreTests` (offline) and by the app/smoke-test
/// targets to synthesize a tiny known audio file for the "Test Groq
/// connection" button (blueprint Step 5a task 3) and the standalone
/// integration smoke test, without needing Mihir's mic or a fixture file
/// checked into the repo.
public enum WAVEncoder {
    /// `durationSeconds` of digital silence (all-zero samples) — enough to
    /// prove the HTTP round-trip and response parsing work; not meant to
    /// produce a real transcript.
    public static func makeSilentWAV(durationSeconds: Double, sampleRate: Double = TargetAudioFormat.sampleRate) -> Data {
        let sampleCount = max(1, Int((durationSeconds * sampleRate).rounded()))
        return encode(pcm16Samples: [Int16](repeating: 0, count: sampleCount), sampleRate: sampleRate)
    }

    /// A short sine tone — an alternative synthetic test signal (non-silent,
    /// still not real speech) for exercising the same endpoint a second way.
    public static func makeToneWAV(
        durationSeconds: Double,
        frequencyHz: Double = 440,
        sampleRate: Double = TargetAudioFormat.sampleRate,
        amplitude: Double = 0.2
    ) -> Data {
        let sampleCount = max(1, Int((durationSeconds * sampleRate).rounded()))
        var samples = [Int16](repeating: 0, count: sampleCount)
        for index in 0..<sampleCount {
            let t = Double(index) / sampleRate
            let value = amplitude * sin(2 * Double.pi * frequencyHz * t)
            samples[index] = Int16(max(-32767, min(32767, (value * 32767).rounded())))
        }
        return encode(pcm16Samples: samples, sampleRate: sampleRate)
    }

    /// Encodes mono 16-bit PCM samples into a standard 44-byte-header WAV
    /// container (RIFF/WAVE/fmt /data chunks, all little-endian per spec).
    public static func encode(pcm16Samples samples: [Int16], sampleRate: Double) -> Data {
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channelCount) * UInt32(bitsPerSample / 8)
        let blockAlign = channelCount * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * MemoryLayout<Int16>.size)
        let riffChunkSize = 36 + dataSize

        var data = Data()
        func appendASCII(_ string: String) { data.append(Data(string.utf8)) }
        func appendUInt32LE(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func appendUInt16LE(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        appendASCII("RIFF")
        appendUInt32LE(riffChunkSize)
        appendASCII("WAVE")

        appendASCII("fmt ")
        appendUInt32LE(16) // PCM fmt sub-chunk size
        appendUInt16LE(1)  // audio format 1 = PCM
        appendUInt16LE(channelCount)
        appendUInt32LE(UInt32(sampleRate))
        appendUInt32LE(byteRate)
        appendUInt16LE(blockAlign)
        appendUInt16LE(bitsPerSample)

        appendASCII("data")
        appendUInt32LE(dataSize)
        for sample in samples {
            appendUInt16LE(UInt16(bitPattern: sample))
        }

        return data
    }

    /// Reads the `fmt `/`data` chunk sizes back out of a WAV file's own
    /// header to recover its duration — the inverse of `encode`, used by
    /// `GroqTranscriptionEngine` to scale its request timeout to the actual
    /// recording length instead of a flat budget. Walks chunks generically
    /// (doesn't assume `fmt ` comes immediately before `data`, or that the
    /// header is exactly 44 bytes) since this only needs to be correct for
    /// any valid PCM WAV, not just the fixed layout `encode` happens to
    /// produce. Returns `nil` for anything malformed rather than crashing —
    /// callers fall back to a fixed floor.
    public static func durationSeconds(ofWAVData data: Data) -> Double? {
        guard data.count >= 12,
              data[data.startIndex..<data.startIndex + 4].elementsEqual(Array("RIFF".utf8)),
              data[data.startIndex + 8..<data.startIndex + 12].elementsEqual(Array("WAVE".utf8))
        else { return nil }

        var offset = data.startIndex + 12
        var byteRate: UInt32?
        var dataChunkSize: UInt32?

        func readUInt32LE(at position: Data.Index) -> UInt32? {
            guard position + 4 <= data.endIndex else { return nil }
            return data[position..<position + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
        }

        while offset + 8 <= data.endIndex {
            let chunkID = data[offset..<offset + 4]
            guard let chunkSize = readUInt32LE(at: offset + 4) else { return nil }
            let chunkBodyStart = offset + 8

            if chunkID.elementsEqual(Array("fmt ".utf8)) {
                guard chunkBodyStart + 16 <= data.endIndex,
                      let rate = readUInt32LE(at: chunkBodyStart + 8)
                else { return nil }
                byteRate = rate
            } else if chunkID.elementsEqual(Array("data".utf8)) {
                dataChunkSize = chunkSize
            }

            // Chunks are word-aligned: an odd-sized chunk has a padding
            // byte after it that isn't part of `chunkSize`.
            let paddedSize = Int(chunkSize) + (chunkSize % 2 == 1 ? 1 : 0)
            offset = chunkBodyStart + paddedSize
        }

        guard let byteRate, byteRate > 0, let dataChunkSize else { return nil }
        return Double(dataChunkSize) / Double(byteRate)
    }
}
