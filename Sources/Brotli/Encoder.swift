// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Bytes

/// Top-level encoder orchestrator. The public entry point is
/// ``Brotli/compress(_:quality:)``.
///
/// v0.2 stub — the real pipeline arrives in tasks 2–8 of the v0.2
/// implementation plan. The empty-input fast path is canonical:
/// a single byte `0x06` is the shortest valid brotli stream
/// (WBITS=10 prefix + ISLAST=1 + ISLASTEMPTY=1 + byte align).
enum Encoder {
    static func encode(_ bytes: Bytes, quality: Brotli.Quality) throws(BrotliError) -> Bytes {
        let q = quality.rawValue
        guard q >= 0 && q <= 11 else { throw .qualityOutOfRange }
        guard bytes.count <= Brotli.maxInputSize else { throw .inputTooLarge }
        // STUB: emit minimal valid empty brotli stream for any input until
        // tasks 2–8 wire in the real pipeline.
        if bytes.isEmpty {
            return Bytes([0x06])
        }
        // Sentinel: not implemented yet for non-empty input. Replaced in T8.
        throw .inputTooLarge
    }
}
