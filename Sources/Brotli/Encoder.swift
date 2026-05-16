// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Bytes

/// Top-level encoder orchestrator. The public entry point is
/// ``Brotli/compress(_:quality:)``.
///
/// Pipeline:
/// 1. Validate quality + input size.
/// 2. Emit stream header (WBITS=22 — fixed for v0.2).
/// 3. Scan input via ``MatchFinder`` to produce a command stream.
/// 4. Emit one metablock containing the entire command stream.
/// 5. Byte-align and return.
///
/// v0.2 uses one metablock per `compress()` call. Window size LGWIN=22
/// (4 MiB) regardless of input length.
enum Encoder {
    static func encode(_ bytes: Bytes, quality: Brotli.Quality) throws(BrotliError) -> Bytes {
        let q = quality.rawValue
        guard q >= 0 && q <= 11 else { throw .qualityOutOfRange }
        guard bytes.count <= Brotli.maxInputSize else { throw .inputTooLarge }

        var w = BitWriter()

        // Stream header. WBITS=22 per RFC 7932 § 9.1: first bit 1, next 3
        // bits encode WBITS-17 = 5. LSB-first emit:
        //   bit0=1 (first)
        //   bits1-3 = numeric 5 LSB-first → bit1=1, bit2=0, bit3=1
        // As a 4-bit value: 0b1011 = 11.
        w.writeBit(1)
        w.writeBits(5, count: 3)

        // Scan + emit metablock.
        let commands = MatchFinder.scan(bytes, quality: quality)
        EncoderMetaBlock.emit(commands: commands, inputSize: bytes.count, isLast: true, to: &w)

        // Final byte-align so the stream ends on a byte boundary.
        w.alignToByte()

        return w.finalize()
    }
}
