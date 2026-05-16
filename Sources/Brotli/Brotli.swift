// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Bytes

/// Sendable, Foundation-free [RFC 7932](https://www.rfc-editor.org/rfc/rfc7932.html)
/// Brotli codec.
///
/// **Decode** (since v0.1):
///
/// ```swift
/// import Brotli
/// import Bytes
///
/// let compressed: Bytes = ...
/// let plain = try Brotli.decode(compressed)
/// ```
///
/// **Compress** (since v0.2):
///
/// ```swift
/// let plain: Bytes = ...
/// let compressed = try Brotli.compress(plain)
/// // or with explicit quality:
/// let smaller = try Brotli.compress(plain, quality: .smallest)
/// ```
///
/// Per [RFC-0017](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0017-phase-12-anchor-brotli-encoder.md),
/// v0.2 is one-shot only and skips static-dictionary search,
/// multi-metablock partitioning, and advanced literal-context modeling.
/// The compressor produces **valid** brotli streams that round-trip via
/// ``decode(_:)`` and the reference `brotli` CLI but does NOT match the
/// reference encoder's compression ratio.
public enum Brotli: Sendable {
    /// Default output cap to prevent decompression bombs.
    public static let defaultOutputCap = 64 * 1024 * 1024  // 64 MiB

    /// Encoder input cap. v0.2 is one-shot; inputs larger throw
    /// ``BrotliError/inputTooLarge``.
    public static let maxInputSize = (1 << 24) - 1  // 16 MiB - 1

    /// Decode a complete brotli stream.
    public static func decode(_ bytes: Bytes) throws(BrotliError) -> Bytes {
        try Decoder.decode(bytes, outputCap: defaultOutputCap)
    }

    /// Compress bytes to a brotli stream.
    ///
    /// `quality` accepts the RFC 7932 0..11 range. v0.2 implements the
    /// algorithmic difference as match-search depth only — higher quality
    /// finds longer / further matches at correspondingly higher CPU cost.
    /// Quality 0 is a literal-only fast path that compresses nothing but
    /// emits a valid brotli stream.
    public static func compress(_ bytes: Bytes, quality: Quality = .default) throws(BrotliError) -> Bytes {
        try Encoder.encode(bytes, quality: quality)
    }

    /// Compression quality tiers per RFC 7932.
    public enum Quality: Sendable, Equatable, Hashable {
        /// Level 0 — literal-only fast path. No compression; emits a valid
        /// brotli stream of size approximately input + 5% framing overhead.
        case fastest
        /// Level 4 — shallow match search.
        case fast
        /// Level 6 — balanced default.
        case `default`
        /// Level 9 — deeper match search.
        case balanced
        /// Level 11 — deepest match search (no static-dictionary search
        /// in v0.2; ceiling is algorithmically the same as level 9).
        case smallest
        /// Explicit numeric level; throws ``BrotliError/qualityOutOfRange``
        /// if outside `0...11`.
        case level(Int)

        /// The RFC 7932 quality level (0..11) this case represents.
        public var rawValue: Int {
            switch self {
            case .fastest: return 0
            case .fast: return 4
            case .default: return 6
            case .balanced: return 9
            case .smallest: return 11
            case .level(let n): return n
            }
        }
    }
}

extension Brotli {
    /// Streaming encoder namespace (v0.3+). For one-shot compression of
    /// bounded inputs ≤16 MiB, use ``Brotli/compress(_:quality:)``.
    public enum Streaming: Sendable {}
}
