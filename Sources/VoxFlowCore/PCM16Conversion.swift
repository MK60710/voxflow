import Foundation

/// Pure Float32 → 16-bit signed PCM sample conversion — no AVFoundation
/// dependency, so it's directly Swift-Testing-able offline (see
/// `PCM16ConversionTests`).
///
/// **Why this exists (perf-fix context, not a blueprint step):** `AudioRecorder`
/// used to write its on-disk WAV file (the exact bytes uploaded to Groq's
/// `/audio/transcriptions`) as 32-bit float PCM, straight from the same
/// Float32 samples `MonoPCMBuffer`/`SilenceDetector` use internally. Whisper-
/// family models (including Groq's `whisper-large-v3-turbo`) expect and work
/// fine with 16-bit PCM, so every recording was uploading exactly 2x the
/// bytes it needed to for no transcription-quality benefit — real, avoidable
/// upload latency on every dictation. This type is the scaling/clamping math
/// for the fix; `AudioRecorder` calls it only when producing the on-disk
/// file, never when building the in-memory `MonoPCMBuffer` `SilenceDetector`/
/// "Play last recording" playback still use, so this change is isolated to
/// the final on-disk/upload encoding step.
public enum PCM16Conversion {
    /// Converts one Float32 sample (nominal range [-1.0, 1.0], per standard
    /// PCM convention) to a 16-bit signed PCM sample.
    ///
    /// Two things worth being deliberate about here, since a botched
    /// conversion produces garbage/distorted audio, not just a crash:
    /// 1. **Clamp before scale.** Real mic input can briefly exceed ±1.0
    ///    (observed on real hardware, not just theoretical) — clamping first
    ///    means the scale step never has to reason about out-of-range input.
    /// 2. **Scale by 32767, not 32768.** Symmetric scaling keeps both
    ///    directions within Int16's representable range (-32768...32767)
    ///    with a single rounding step and no possibility of the +1.0 case
    ///    rounding to 32768 and overflowing Int16.max — the classic off-by-
    ///    one bug this exact conversion invites. The cost is that Int16's
    ///    most-negative value (-32768) is technically never produced, which
    ///    is an inaudible, standard trade-off (same convention many PCM
    ///    encoders use) rather than a lost bit of precision that matters for
    ///    speech transcription.
    public static func int16Sample(fromFloat32 sample: Float) -> Int16 {
        let clamped = max(-1.0, min(1.0, sample))
        let scaled = (clamped * 32767.0).rounded()
        // Belt-and-suspenders: `scaled` is mathematically guaranteed to be
        // within [-32767, 32767] once `clamped` is within [-1, 1], but an
        // explicit clamp to Int16's actual range costs nothing and makes the
        // "never overflow" property hold even if the math above is ever
        // changed without re-deriving this guarantee.
        let boundedScaled = max(Float(Int16.min), min(Float(Int16.max), scaled))
        return Int16(boundedScaled)
    }

    /// Converts a full buffer of Float32 samples to 16-bit signed PCM, in
    /// order, one-to-one.
    public static func convert(_ samples: [Float]) -> [Int16] {
        samples.map(int16Sample(fromFloat32:))
    }
}
