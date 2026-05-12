// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Bytes

/// Sendable, Foundation-free [RFC 7932](https://www.rfc-editor.org/rfc/rfc7932.html)
/// Brotli decoder. Single-shot: takes a complete brotli bit stream and
/// returns the decompressed `Bytes`.
///
/// ```swift
/// import Brotli
/// import Bytes
///
/// let compressed: Bytes = ...   // raw brotli stream
/// let plain = try Brotli.decode(compressed)
/// ```
///
/// Per [RFC-0015](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0015-phase-10-anchor-brotli-decoder.md),
/// **v0.1 ships decoding only**. The encoder lands in a future minor release.
public enum Brotli: Sendable {
    /// Default output cap to prevent decompression bombs. Configurable
    /// per-call once streaming lands; v0.1 uses this constant.
    public static let defaultOutputCap = 64 * 1024 * 1024  // 64 MiB

    /// Decode a complete brotli stream.
    public static func decode(_ bytes: Bytes) throws(BrotliError) -> Bytes {
        try Decoder.decode(bytes, outputCap: defaultOutputCap)
    }
}
